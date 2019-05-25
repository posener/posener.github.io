---
layout: post
title: Goroutine Scoped Context Proposal
keywords: go,golang,context,scope,proposal,go2,
github: https://github.com/posener/context
---

The context design in Go is beautiful and powerful.
But like all things, it also can be improved.
In this post I will present the major problems I currently see in the context system,
a backward compatible solution to those problems,
and a proof of concept library that implements a demo of the solution.
Hopefully, you'll be convinced that this change is necessary and can
improve the user experience in the Go language.

I think that the problems I raise here are painful to a lot of Go programmers,
and I could only hope that this post will result in an effort
towards a solution, or be an inspiration for a better solution.

:heart: I would love to know what you think, both on the raised problem and on the proposed solution.
Please use the comments platform on the bottom of the page for this kind of discussion.

## Problem Statement

Context problems that are addressed by this proposal:

### 1. Context Propagation

**Explicitness**.
The current context implementation is very explicit, which is a good thing.
It allows the programmer to know exactly where context is modified,
and what it is going to influence.

But, it is **too explicit**.
The context biggest problem is that it is a virus.
You must pass it around everywhere.

Let's take a classic example.
Consider the case that we have a call stack of 100 functions.
The 100th function is the only one that needs the context and the context is
passed to the 1st function.
There are two ways to deal with this issue.

```go
func f1(ctx context.Context) {
	f2()
}

func f2() {
	f3()
}

[ ... f3 through f98 ... ]

func f99() {
	f100(context.TODO()) // TODO: Use the right context
}

func f100(ctx context.Context) {
	<-ctx.Done()
}
```

The **wrong** way to solve this case is to store the context in a place
which is globally available.
We'll elaborate on it later.

The **right** way to solve this case is to update 98 functions.
Each function needs to be updated to accept the context as it's first argument
and to call the next function in the stack with that context object:

```diff
 func f1(ctx context.Context) {
-	f2()
+	f2(ctx)
 }

-func f2() {
+func f2(ctx context.Context) {
-	f3()
+	f3(ctx)
 }

 [ ... f3 through f98 ... ]

-func f99() {
+func f99(ctx context.Context) {
-	f100(context.TODO())
+	f100(ctx)
 }

 func f100(ctx context.Context) {
 	<-ctx.Done()
 }
```

This solution works, but it has drawbacks:

1. There is a burden in updating all function calls to accept the context
   and to pass it following calls, all along the call stack.
2. Functions that have nothing to do with context, become aware of the context.
   It is distracting and increases the risk of introducing new bugs.
3. It could lead to code duplication or an increase in API surface.
   For example, in the case of public API that should maintain backward compatibility.
   Let's suppose that the private `f22` was a public `F22`.
   The new code that is context aware will be:

   ```go
   // F22 remains with the same signature to preserve backward
   // compatibility.
   func F22() {
   	F22Context(context.Background())
   }

   // F22Context has the new needed functionality of accepting and
   // passing the context.
   func F22Context(ctx context.Context) {
   	f23(ctx)
   }
   ```

   This change might be backward compatible, but it might also be wrong.
   What exactly does it mean that `F22` is using `context.Background()` as
   the context?
   Was it more correct to use `context.TODO()`?
   Should we deprecate `F22`?

   This pattern can be found in the standard library where public functions
   had to be adjusted for context when it was introduced.
   For example: `net.Dial`/`net.DialContext` and `sql.Exec`/`sql.ExecContext`.

4. If somewhere in the middle of the call stack we don't have
   control on the code, we can't use the context at all.

   For example,
   the very popular ORM library [GORM](https://github.com/jinzhu/gorm)
   still [does not support context](https://github.com/jinzhu/gorm/issues/1231).
   Since the context must be passed explicitly through the entire call stack,
   GORM users can't enjoy the benefits of using the context in SQL queries,
   even though the `sql` package does support it.

The explicitness of context is it's strength.
But, it does come with a price.
The current context system might cause high overhead, distracting code,
high API exposure, backward compatibility issues and impossible implementations.

### 2. The Context Should not be Stored

The proposed "wrong" solution to the problem mentioned in the previous chapter
was to store the context in a global place.

Let's discuss two wrong solutions:

- Use a global variable.

  ```diff
  +var gCtx context.Context

   func f1(ctx context.Context) {
  +	gCtx = ctx
   	f2()
   }

   func f2() { f3() }
  
   [ ... f3 through f99 remain unchanged ... ]

  -func f100(ctx context.Context) {
  +func f100() {
  -	<-ctx.Done()
  +	<-gCtx.Done()
   }
  ```

  This solution is very wrong.
  For instance, it will fail for concurrency reasons.
  If we call `f1` from two different goroutines concurrently,
  concurrent calls to `f1` will override `gCtx`,
  which will allow `f100` of the first call to read the context of the second call.

- Create a struct that will hold the context.

  ```diff
  +type fs struct {ctx context.Context}

   func f1(ctx context.Context) {
  -	f2()
  +	f := fs{ctx: ctx}
  +	f.f2()
   }

  -func f2() { f3() }
  +func (f *fs)f2() { f.f3() }

   [ ... f3 through f99 with the same change ... ]

  -func f100(ctx context.Context) {
  +func (f *fs)f100() {
  -	<-ctx.Done()
  +	<-f.ctx.Done()
   }
  ```

  This requires quite a big change, and most of the times it won't
  be as easy as in the example above.
  Gladly, this code is safe for concurrent usage.
  However, this is also not a good solution.
  Let's understand why.

The `context` package documentation contains the following paragraph,
to which I added my thoughts.

> Programs that use Contexts should follow these rules to keep interfaces
> consistent across packages and enable static analysis tools to check
> context propagation:

The mentioned required linters,
[are yet to exist](https://github.com/golang/go/issues/16742).

> Do not store Contexts inside a struct type; instead, pass a Context explicitly
> to each function that needs it.

In this line we are instructed to choose the first solution over the second solution.
It made me wonder, why should there be rules about how to use the context object?

> The Context should be the first parameter, typically named ctx:
>
>     func DoSomething(ctx context.Context, arg Arg) error {
>     	// ... use ctx ...
>     }

This is a convention. Which is OK.
But it is left to the programmer to be aware of it and to follow it.
This is very uncharacteristic for Go, very different than `go fmt` for example.

> Do not pass a nil Context, even if a function permits it.

Another rule, OK.
Again, the programmer needs to be aware of it.

> Pass `context.TODO` if you are unsure about which Context to use.

What does it mean?
How can I be unsure which context to use?
Especially with the current design where creating, modifying and passing the
context is so explicit?

Let's review the simple rules that we must obey:

1. Always pass the context by function calls (preferably always as first argument).
2. Store the context only in a function local variable.
3. Context value should never be nil.

And maybe a fourth rule, if the second one was not clear enough:
**never** store the context in any struct or global variable.

These are strict rules.
Even the standard library itself finds it hard to follow them.
The common [`http.Request`](https://golang.org/pkg/net/http/?#Request)
struct violates the second rule and contains a `ctx` field, with a remarkable comment:

```go
type Request struct {
	...
	// ctx is either the client or server context. It should only
	// be modified via copying the whole Request using WithContext.
	// It is unexported to prevent people from using Context wrong
	// and mutating the contexts held by callers of the same request.
	ctx context.Context
}
```

I suspect that this implementation is the only option that was given
for adding a context to the request handling without breaking APIs such as the
[`http.Handler`](https://golang.org/pkg/net/http/?#Handler) interface.
The current way to implement `http.Handler` and get the context object
is using the request object `Context` function:

```go
func (handle)ServeHTTP(r *http.Request, w http.ResponseWriter) {
	ctx := r.Context()
	// use ctx...
}
```

This technically violates the first rule of the context -
the context is not passed as the first argument.
I am guessing that when the context was introduced to the standard library,
adding context to the http stack could be implemented in two ways:

1. To duplicate APIs. Add another interface that accepts the context object
   in the standard way:

   ```go
   type HandlerContext interface {
   	ServeHTTP(context.Context, *http.Request, http.ResponseWriter)
   }
   ```

2. Inject the context into the `http.Request` object. And keep the interface as is.

The solution of attaching the context to the request object was more backward compatible
and called for less API additions. Keeping the http package API clean as it used to be.
It only demands the violation of the context rules and a shallow copy
(with the `WithContext` method) of the request object whenever the context should be updated.

The current implementation of the context system encourages such infractions.
The rules are strict and it is easy to disregard them when too many changes are committed.

We might also be thankful that this was the implementation chosen for the `http` package.
But should we also do the same in our own libraries?

Why is it so important to follow the context rules?
Let's examine the case of `http.Request`:

1. The request object becomes our context manager.
   Instead of using the context object, we usually find ourselves passing
   the request object.
   For example, consider a function `f` that needs both the context and the request.
   Usually, `f` will be implemented as follows:

   ```go
   func f(req *http.Request) {
   	ctx := req.Context()
   	// Use req and ctx...
   }
   ```

   Where it should have been implemented as:

   ```go
   func f(ctx context.Context, req *http.Request) {
   	// Use req and ctx...
   }
   ```

   The reason that it would not be implemented in the second way is that it's call will
   look funny and wrong: `f(req.Context(), req)`.
   This is the point where `req` of type `*http.Request` becomes the context manager.

2. If `http.Request` becomes the context manager, updating the context becomes
   tedious and ugly:

   ```go
   // Extracting the context
   ctx := req.Context()
   // Updating the context
   ctx = context.WithValue(ctx, key, value)
   // Updating the context's box
   req = req.WithContext(ctx)
   // Use the box as the context
   f(req)
   ```

3. It might make things confusing.
   Suppose that we have the second implementation of `f`. Which context should you use?

   ```go
   func f(ctx context.Context, req *http.Request) {
   	// Use req and ctx...
   	// But wait! should we use ctx or req.Context()?
   }
   ```

In order to utilize the powers of the context,
we must obey the rules but the rules are strict so it is sometimes tempting to workaround them.
This is usually done by storing the context, which may have bad implications.
In essence, the current design of the context system encourages
workarounds - and that is why its rules were made up in the first place.

### 3. The Existence of `context.TODO`

We've met the `TODO` already.
The `TODO` is actually a "workaround", for the design of the current context system.
This is the documentation:

> TODO returns a non-nil, empty Context.
> Code should use `context.TODO` when it's unclear which context to use or it is not yet
> available (because the surrounding function has not yet been extended to accept a
> Context parameter).
> TODO is recognized by static analysis tools that determine whether
> Contexts are propagated correctly in a program.

According to this paragraph, the
existence of `context.TODO` is basically proof of that there are problems.
We "should use `context.TODO` when" something is "unclear" (problem #2) or
"not yet available" (problem #1).
If those problems did not exist, so `context.TODO` would not exist.

The irony with the `TODO` implementation is that with all the explicitness that the context
package provides, it is still "unclear which Context to use or it is not yet available".

## Proposal

This proposal discusses an approach of storing the context in the goroutine struct,
referred to as "**goroutine scoped context**".
We will see how it can solve all the enumerated problems, without any compromises.

Storing a context object in a "goroutine local storage"
(analogue to [thread-local storage](https://en.wikipedia.org/wiki/Thread-local_storage)),
was already discussed in Github issue
[#21355](https://github.com/golang/go/issues/21355).
The issue discussion had diverged from the original purpose,
and the proposal did not cover the essence of the given problem.
Eventually the issue was closed for reasons that are not related to this proposed solution.

The proposal is comprised of several required changes, which will define
the language API for goroutine scoped context.
After which, we will discuss the correctness of this new definitions.

### 1. Store a Context object in the Goroutine Struct

First we need to enable the storage of a context object in the goroutine struct.
The storage of the context object will be a stack, as we will see in advanced stages of this proposal.
We will assume it is possible and dismiss threats of cyclic dependencies between
the packages as "implementation details".

This stage goes hand in hand with a second stage:

### 2. Add Accessor functions Goroutine Context

The following goroutine context accessor functions should be added
to the `context` package:

1. A call to `context.Set` will push the new context to the stack,
   and will return an `unset` function that should be used to pop the pushed context.
   The result is that the context scope starts on call to `context.Set`,
   and ends on call to the returned `unset` function.

2. A call to `context.Get` will return the context in the top of the stack.

Usage Example:

```go
defer context.Set(ctx)()
// Context scope is from here to the end of the function.
```

The unset function can be called explicitly:

```go
unset := context.Set(ctx) // ctx scope begins
// The scope
[ ... ]
unset() // ctx scope ends
```

### 3. Update `go` to Propagate the Context

A new goroutine will have a new stack initiated with one element containing the context
from the top of the parent goroutine stack.
When goroutine **A** is invoking a new goroutine **B**, **B** should have a stack
containing **A**'s top context.

### 4. Enable `go` with Context

In case that the invoked goroutine should have a different context than it's
parent context, we need an option to pass a different context.
This could be done by adding an option to run a goroutine with a specific context:
Using `go ctx f()`, or `go ctx, f()`, or any other syntax change.

The new go command could be run with a function call, which is the default behavior
of propagating the parent context to the new goroutine.
Or with context object and a function call, which is the new behavior of defining a
specific context to the new goroutine.

This change is backward compatible, since calling `go` with two argument in not allowed.
Additionally, checking that `ctx` is of type `context.Context` can be done in compile time.

If language syntax modification is a limitation here, see
[appendix I](#appendix-i---syntax-change-alternative).

### Philosophy

Now that we have defined the goroutine scoped context API,
we have the tools to wonder about its essence:

#### "Should Goroutines Have a Context?"

Dave Chaney wrote a post called "Context isn't for cancellation"
[blog post](https://dave.cheney.net/2017/08/20/context-isnt-for-cancellation).
Even though I disagree with the main issue raised in this post,
Dave raises a good and valid point: the context object has two independent roles.
Two roles packed into one object.

It will be easier to address the need for goroutine scoped context
if we inspect those two independent roles independently:

1. **Liveness**: Indicates whether the context is done.
   Inspected by the `Done`, `Err` and `Deadline` methods,
   and controlled by the `context.WithCancel`, `context.WithTimeout` and
   `context.WithDeadline` functions.

   Goroutine scoped context introduces to the Go runtime a substantial capability.
   Any piece of code will be able to know if it should still be running.

   Just to emphasize the strength of such a feature:
   In any piece of code, **literally anywhere**, we could write:

   ```go
   select {
   case <-context.Get().Done(): // WOW!
   	return // I should not be running...
   case task <-tasks:
   	// I should run a task!
   }
   ```

   Additionally, we can tell any piece of code if it should be running.

   Here is an example that shows how to set a timeout to the context of the
   current goroutine:

   ```go
   ctx, cancel := context.WithTimeout(ctx, 100*time.Millisecond)
   defer cancel()
   context.Set(ctx)
   // Following functions, or invoked goroutines will be
   // timed-out after 100 milliseconds.
   ```

   It is no longer needed to explicitly pass a context.
   This could replace the classic cancellation signaling by an empty-struct "done" channel,
   which is no longer needed.
   There is a new, one, standard way to indicate if a a running code should be done.

2. **Values**: Custom key-value pairs that can be retrieved from the context.
   Inspected by the `Value` method and controlled by the `context.WithValue` modifier.

   Goroutine scoped context introduces a way to ask from any piece of code:
   "What is the value of 'X'?"

   This is a complex question, and I don't have a clear answer.
   Adding a value to the goroutine context should be done
   only if all following code should know the value of "X".
   But this is not always the case -
   For example, consider an HTTP middleware that extracts user credentials from the request
   and adds it to the goroutine context.
   Not all handler code should necessarily know about those credentials.

   But this applies to the current context design as well -
   Consider the given example, just think of request context instead of goroutine context.

   Context values should not be abused and programmers should take good care
   when considering storing values in the context object.

   This proposal does not fix, change, or enhance this aspect of the context, but provides
   a way to obtain those values without explicitly passing the context object through
   a the call stack.

Adding the context accessor functions maintains the
explicitness of the previous context system.
One could follow exactly where the context has been set and has been used.
Additionally, since it does not need to be passed through function calls,
it prevents breaking APIs.
Finally, it eliminates the need to store the context anywhere but a local variable,
and make the decision of choosing the context clear.

We've made arguments as to why the context should be goroutine scoped.
But let's examine why it should not be functioned scoped.

#### "Should Functions Get a Context?"

We've enumerated several points for and against function scoped context.
But we haven't actually discussed its meaning.
Functions group lines of code that are invoked sequentially.
Having a unique context specific for those set of lines, adds no additional
value, in any other case except for testing purposes.

Consider the following code.

```go
func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	f(ctx)
}
```

`main` creates a context with cancel, defer the cancel and runs `f` with the new context.
If `f` was invoked in a new goroutine this code would make a bit of sense.
But running `f` in the same goroutine as `main` makes no sense at all -
the `cancel()` call is cancelling a context that was used for running `f`,
but it is called after `f` was already finished.
As long as `main` and `f` share the same goroutine,
`main` should not pass to `f` any other context but the one it is using.

Goroutine scoped context does not eliminate the option to write the above code,
but it discourages it.
A function should not get the context by argument, but by `context.Get()`.

### Conclusions

This proposal claims that the context object,
which is now function scoped, should be goroutine scoped.

This conception change prevents the need
to pass the context object explicitly through the call stack,
it eliminates the motivation to store the context anywhere but local variable,
and obviates the existence of `context.TODO`.

On the other hand, it maintains the essential code explicitness,
reduces code verbosity, reduces API exposure,
makes easier context adapting for existing code,
and just as important, maintains backward compatibility.

The proposed change makes the context object a first class citizen of Go.
It should be integrated into the goroutine struct and into the `go` keyword syntax.
The reason is that the context object provides go with missing capabilities
of controlling goroutine lifecycle, and storing scoped metadata information.

### Arguments Against this Proposal

I understand that this proposal might be seen as controversial for many Go developers.
Here are my answers to few opinions I expect against the proposal:

#### This Change Result in Mix of High Level and Low level Objects

The context object, which is considered as a high level object, should not
be stored in a low level struct such as the goroutine.

**Answer**: The context should be treated as a first class citizen in Go.
We should understand that the context can solve a lot of problems for Go
programs with just a few adjustments.
And then, we can see how it integrates with all the low level components of the language.

#### Context / Error Similarity

Context should be explicit. It should follow Go idiomatic error handling.
Every function should explicitly accept it as it should explicitly return an error.
And every function call should explicitly pass it, as it explicitly checks the error
return value.

**Answer**: Actually, they are not the same.
In Go's error handling, a function returns an error only if it doesn't handle it.
But when dealing with context, a function should receive it in arguments and
pass it through function calls, even if it has no concern about the context.
Currently you are gratuitously forced to handle context.

Additionally, the Go team has understood that error handling is sometimes a burden,
and makes Go code clumsy.
One of Go 2 proposals deals exactly with this issue, with the name:
[error handling](https://go.googlesource.com/proposal/+/master/design/go2draft-error-handling-overview.md).
It is time to understand that context handling is also sometimes a burden,
and makes Go code more clumsy.

#### Context is for Network Code

The context object is mainly used by the `net` package, and should
not penetrate the other parts of the language.

**Answer**: Even though `context` used to be `x/net/context`,
it is not anymore part of the `net` package.
Despite the fact that the `net` package is its main consumer,
it is also being used by packages like
`database/sql`, `os/exec`, `runtime/trace`, `runtime/pprof`, `cmd/vet` and more.

In this proposal I tried to emphasize the importance of the role that the context
can take in managing goroutine lifecycle,
in the general form, and not only in network context.

## Proof of Concept

Inspired by [a8m](https://github.com/a8m)'s idea,
I've implemented a simplified version of the proposed solution
without any changes to the standard library.
It is available on [github.com/posener/context](https://github.com/posener/context).

The purpose of this library is only to give a sense of how context in goroutines will be like,
if it would was appropriately implemented.

Instead of modifying the goroutine struct to contain the context,
this implementation stores the context in a global map according to a goroutine ID.
Instead of changing the behavior of the `go` keyword,
this implementation contains `context.Go` and `context.GoCtx`.
Please check out the [README](https://github.com/posener/context/blob/master/README.md)
for more details.

### Examples

The default behavior of new goroutines is to get the parent goroutine context:

```go
// If here: context.Get() == ctx1
go func() {
	// Then also here: context.Get() == ctx1
}()
```

New goroutines can be run with a different context:

```go
ctx := context.Get()
// At this point: context.Get() == ctx
ctx, cancel := context.WithTimeout(ctx, duration)
defer cancel()
// ctx was changed so: context.Get() != ctx
go ctx func() {
	// New goroutine invoked with new context: context.Get() == ctx
}()
```

The goroutine context can be changed, this will be reflected inside
invoked goroutine and invoked functions.

```go
ctx := context.Get()
// At this point: context.Get() == ctx
ctx, cancel := context.WithTimeout(ctx, duration)
defer cancel()
// ctx was changed so: context.Get() != ctx
unset = context.Set(ctx)
// Goroutine context was updated, so: context.Get() == ctx
go func() {
	// New goroutine invoked with patent context: context.Get() == ctx
}()
f() // Inside f: context.Get() == ctx
unset()
// after unsetting the context context.Get() != ctx
```

## Appendices

### Appendix I - Syntax Change Alternative

An alternative for the `go ctx f()` syntax.

Another option is to add another function to the `context` package:

```go
func Go(ctx Context, f func()) {
	go func() {
		defer Set(ctx)
		f()
	}()
}
```

This function will run `f` in a new goroutine with the given `ctx`.
This solution is less preferable than changing the `go` keyword:
**(1)** Two unimportant function calls are added to the stack,
and **(2)** it limits the function signature to be `func()`,
so more complicated functions should be wrapped with a `func() {}`.

### Appendix II - Adopting New Conventions

First, new functions should not have the context as their first argument.
It is no longer needed.

```diff
-func f(ctx context.Context) {
+func f() {
+	ctx := context.Get()
 }
```

Old functions that accept the context object should be deprecated:

```diff
+// Deprecated, use g instead.
 func f(ctx context.Context) {
 	// Use ctx...
 }

+func g() {
+	ctx := context.Get()
+	f(ctx)
+}
```

New code that uses old-style context accepting functions can simply
pass `context.Get()`:

```diff
-f(context.TODO())
+f(context.Get())
```

## Thanks

Thanks for the feedback by [Philip Pearl](http://disq.us/p/1wh0mba)
and [yimmy149](http://disq.us/p/1wh8r8j) on a previous version of this post.
They enlightened me with a fundamental mistake in one of the assumptions I made.
This mistake is now fixed in this proposal.
