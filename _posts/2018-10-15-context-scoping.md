---
layout: post
title: Go Context Scoping Part 2
keywords: go,golang,context,scope
github: https://github.com/posener/context
---

Thanks for the feedback on the [previous blog post](/goroutine-scoped-context) by
[Philip Pearl](http://disq.us/p/1wh0mba) and [yimmy149](http://disq.us/p/1wh8r8j),
I understood that I had a fundamental mistake in one of the assumptions I made.
As a result, the [proposed solution](/goroutine-scoped-context/#proposal) has a bug,
as the claim that context is goroutine-scoped appears to be wrong.
However, I still believe that the
[problem statement](/goroutine-scoped-context/#problem-statement) is correct,
and the positive feedback I got
encouraged me to improve the design, and offer a better solution.

:heart: I would love to know what you think.
Please use the comments platform on the bottom of the page for this kind of discussion.

## Context Scope <= Goroutine Scope

[Philip Pearl](http://disq.us/p/1wh0mba) and [yimmy149](http://disq.us/p/1wh8r8j)
pointed that the context scope is contained within the goroutine scope,
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
Since the proposed design treats both of those scopes as one,
it fails the program's logic.

> In more detailed,
> the `main` function sets a cancellable context and defer the cancellation.
> It then calls `foo`, and expects that `foo` will have no effect on the context.
> So after the call to `foo` the context will have no error -
> since the cancel haven't been called yet.
> The `foo` function also sets a cancellable context and defers the cancellation.
> When `foo` exits, `cancel` is called and the goroutine scoped context is now cancelled.
> This context is applied outside `foo` since it is goroutine scoped.
> The result is that `main`'s expectations will fail.

The example contradicts the claim in the previous post that the context is goroutine scoped,
and shows that the proposed solution is wrong.

Next, we will see the fix to the solution from the previous post.

## Solution

The solution to the described problem is to stack the context in the
goroutine instead of setting them.
When we enter a context scope we will push a context object to the stack
and we will pop it when we exit the context scope.
The stack itself still needs to be goroutine scoped,
so we won't mix contexts from different goroutines.
In the enumerated options below we can examine different approaches
for managing the context stack.

### Option 1: Scoped `Set` Function

Consider the [original proposal](/goroutine-scoped-context/#proposal) with a slight change.

1. A call to `context.Set` will push the new context to the stack,
   and will return an `unset` function that should be used to pop the pushed context.
   The result is that the context scope starts on call to `context.Set`,
   and ends on call to the returned `unset` function.

2. Using `context.Get` will just return the context in the top of the stack.

3. Invoking a goroutine will create a new stack containing the context from the top
   of the parent goroutine stack.

> The names `Set` and `unset` where chosen because of similarity to the previous
> solution. This should be discussed.

#### Usage Example

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
the example valid.

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

#### Implementation

A proof of concept implementation of this solution was pushed to the
[github.com/posener/context](https://github.com/posener/context) package.

Let's discuss this solution.

#### Advantages

1. **Explicit** context scope: The scope is between two function calls.
   It is very clear when the scope starts and ends.
2. **Flexible** context scope: We can place the function calls wherever we want.
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

4. **Minimal**: The context is only defined when needed.
   Code is more concise.
   Efficiency wise, the context is only copied when it is set
   (not on every function call in the stack as in the current implementation).

#### Drawbacks

1. Calling the returned `unset` function is crucial.
   However, this is similar to other basic designs in the Go standard library,
   such as calling `Close` function of an opened file, or HTTP response body.
   A linter rule could remind us of forgotten calls to `unset`.

2. It might look ugly.
   The API of retuning a function which should be called or deferred is a bit weird.
   It might be less intuitive and harder for people to learn.

   It also makes the code more verbose about the context - a line of code to create
   the context, another line to set it, another one to unset it, these are a lot
   of lines that distract us from the pure business logic of our code.

   On the other hand, this verbose code will only appear in places that we
   are actually concerned about the context.

   A solution to this problem might be by helper functions.
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

   However, I am not sure about the necessity.

### Option 2: Function Scope

Option 1 is very explicit and flexible.
It gives us fine grained control over the context scope's beginning and ending.
But maybe, the current solution of function scope context is good enough.

Combining the goroutine context stack with the current context scoping
might yield an interesting solution.

This solution needs a new syntax for calling a function with context,
when the function did not provide it as one of its arguments.

If such syntax exists, we could call function `foo` with context `ctx`.
Then `ctx` will be set before `foo` is called,
and will be unset after `foo` finishes. Something similar to this code
(without the function wrapping of course):

```go
func() {
	defer context.Set(ctx)()
	foo()
}()
```

Calling `context.Get()` inside `foo` will return `ctx`.

This solution basically makes any function accept the
context argument even though it did not declared it.

Can we think of any syntax that won't break Go code?

I thought of something crazy, however, I'm not sure about its feasibility.
What if every function will have two signatures?
The signature that it currently has, and another one containing
the context as the first argument.
For example, a function with signature `foo(int, string)` will implicitly
have another signature `foo(context.Context, int, string)`.
`foo` could be called with `foo(0, "")` and also with `foo(ctx, 0, "")`.
When the second one is used, this function call will push and pop `ctx`
to and from the stack.

On the other hand, this kind of solution will be weird.
A go developer might find it confusing when the function call and the
function signature are mismatched.

Maybe the best way would be to wait for Go2 to come up with a fit
syntax for handling context scopes.

Your opinion about such a solution is welcomed.

## Conclusions

After investigating the shortcomings of the previous solution,
I suggested two possible interesting options for solving the context problems.

These solutions are explicit, more flexible, and more efficient than the current design.
Additionally they solve the problems that the current design faces.