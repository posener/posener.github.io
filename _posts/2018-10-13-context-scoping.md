---
layout: post
title: Go Context Scoping
---

Thanks for the feedback on the [previous blog post](/goroutine-scoped-context) of
[Philip Pearl](http://disq.us/p/1wh0mba) and [yimmy149](http://disq.us/p/1wh8r8j),
I understood that I had a fundamental mistake in one of the assumptions I made.
As a result, the [proposed solution](/goroutine-scoped-context/#proposal) has a bug,
as the claim that context is goroutine-scoped which appear to be wrong.
However, I still believe that the
[problem statement](/goroutine-scoped-context/#problem-statement) is correct.
The modest but supporting feedback I got,
encouraged me to insist in improve the correctness and the design of a solution.

:heart: I would love to know what you think.
Please use the comments platform on the bottom of the page for this kind of discussion.

## Context Scope <= Goroutine Scope

What [Philip Pearl](http://disq.us/p/1wh0mba) and [yimmy149](http://disq.us/p/1wh8r8j)
pointed out is that the context scope is contained within the goroutine scope,
and they are not necessarily the same.
Consider the following simple example:

```go
func main() {
	ctx, cancel := context.WithCancel(context.Get())
	defer cancel()
	context.Set(ctx)
	foo()
	fmt.Println(context.Get().Err() == nil)
	// Prints false since Err() returns "context canceled"
}

func foo() {
	ctx, cancel := context.WithCancel(context.Get())
	defer cancel()
	context.Set(ctx)
}
```

The example contains only one goroutine (the main one) and two context scopes.
The scope of the `main` function matches the first context scope, and the scope
of the `foo` function matches the second context scope.
Since the proposed design treat both of those scopes as one,
it fails the program's logic.

The `main` function sets a cancellable context and defer the cancellation.
It then calls `foo`, and expect that after `foo` the context will have no error -
after all the cancel haven't been called yet.
The `foo` function also sets a cancellable context and defer the cancellation.
When `foo` exits, `cancel` is called and the goroutine scoped context is now cancelled.
This context is applied outside `foo` since it is goroutine scoped.
The result is that `main`'s expectations will fail.

The example contradicts the claim of the previous post that the context is goroutine scoped,
and shows that the proposed solution is wrong.

But let's not give up. Let's try to fix it.

## Solution

The solution to the described problem is instead of setting the context in the goroutine
local storage, we should stack them.
When we enter a context scope we should pop a context object to the stack
and when we exit the context scope we should pop it from the stack.
The stack itself still needs to be goroutine scoped,
so we won't mix contexts from different goroutines.
In the enumerated options below we can examine different approaches
for managing the context stack.

### Option 1: Scoped `Set` Function

Consider the [original proposal](/goroutine-scoped-context/#proposal) with a slight change.
A call to `context.Set` will push the new context to the stack,
and will return an `unset` function that should be used to pop the pushed context.
The result is that the context is scoped between the call to `context.Set`
and the call to the returned `unset` function.

Using `context.Get` will just return the context in the top of the stack.

Invoking a goroutine will create a new stack containing the context from the top
of the parent goroutine stack.

> The names `Set` and `unset` where chosen because of similarity to the previous
> solution. The should be discussed.

Usage example:

```go
unset := context.Set(ctx) // ctx scope begins
// The scope
[ ... ]
unset() // ctx scope ends
```

The call to `context.Set` could also be deferred:

```go
defer context.Set(ctx)()
// Context scope is from here to the end of the function.
```

Rewriting the example above with the updated context package will make
the example correct.

```go
func main() {
	ctx, cancel := context.WithCancel(context.Get())
	defer cancel()
	defer context.Set(ctx)()
	foo()
	fmt.Println(context.Get().Err() == nil)	// Prints true
}

func foo() {
	ctx, cancel := context.WithCancel(context.Get())
	defer cancel()
	defer context.Set(ctx)()
}
```

A proof of concept of this implementation of this solution can be found in the
[scoped-set](https://github.com/posener/context/tree/scoped-set) branch of the
[posener/context](https://github.com/posener/context) package.

Let's discuss this solution.

#### Advantages

1. **Explicit** context scope: The scope is between two function calls.
2. **Flexible** context scope: we can place the function calls wherever we want.
3. There is no longer the need for the `go ctx foo()` syntax.
   As said, new invoked goroutines will contain a new context stack containing
   the top context of the parent goroutine.
   We can now just set a scope with the context that we want in the new goroutine:

   ```diff
   + unset := context.Set(ctx)
   - go ctx foo()
   + go foo()
   + unset()
   ```

#### Drawbacks

1. Calling the returned `unset` function is crucial.
   As other crucial functions (`Close` of an opened file, or HTTP response body)
   it can forgotten.
   This problem, however, could be solved with a linter rule.

2. It might look ugly.
   The API of retuning a function which should be called or deferred is a bit weird.
   It might be less intuitive and harder for people to learn.
   It also makes the code more verbose about the context - a line of code to create
   the context, another line to set it, another one to unset it, those are a lot
   of lines that distract us from the pure  business logic of our code.

   A solution to this problem might be creating helper functions that create a new
   context and set it.
   For example, in the `context` package:

   ```go
   // SetTimeout sets a new context scope with the given timeout.
   // It returns:
   //   - The context cancel function.
   //   - The scope unset function.
   func SetTimeout(duration time.Duration) (CancelFunc, func()){
	   ctx, cancel := WithTimeout(Get(), duration)
	   unset := context.Set(ctx)
	   return cancel, unset
   }
   ```

### Option 2: Function Scope

Option 1 is very explicit and flexible.
It gives us fine grained control over the context scope beginning and ending.
But maybe, the current solution of function scope context is good enough.

Combining the goroutine context stack with the current context scoping
might yield an interesting solution.

This solution needs a new syntax for calling a function with context,
while the function did not provide it as one of its arguments.

If such syntax exists, we could call function `foo` with context `ctx`.
What will happen is that `ctx` will be set before `foo` is called,
and will be unset after `foo` finished. Something similar to this code
(without the function wrapping of coarse):

```go
func() {
	defer context.Set(ctx)()
	foo()
}()
```

Calling `context.Get()` inside `foo` will return `ctx`.

It is basically a solution that makes any function accept the
context argument even though it did not declared it.

Can we think of any syntax that won't break Go code?

I thought of something crazy, which I'll share with you.
However, I'm not sure about it's feasibility.
What if every function will have two signatures?
The signature that it currently has, and another one containing
the context as the first argument.
For example, a function with signature `foo(int, string)` will implicitly
have another signature `foo(context.Context, int, string)`.
`foo` could be called with `foo(0, "")` and also with `foo(ctx, 0, "")`.
When the second one is used, this function call will push and pop `ctx` 
to and from the stack.

On the other hand, this kind of solution will be wierd.
A go developer might find it confusing when the function call and the
function signature mis match.

Your opinion about such a solution are welcomed.

## Conclusions

After investigating the deficiencies of the previous solution,
I gave two possible interesting options for solving the context problems.

The give solutions are explicit, more flexible, and more efficient than the current design.
Additionally they solve the problems that the current design face.

I am sorry about the misleading in the previous post.