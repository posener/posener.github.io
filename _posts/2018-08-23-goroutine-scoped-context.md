---
layout: post
title: Goroutine Scoped Context Proposal
---

The Context design in Go is beautiful and powerful.
As all things, it can also be improved.
In this post I will present the main problems I currently see in the context system,
a backward compatible solution to those problems,
and a proof of concept library that implements a demo of the solution.
Hopefully, I could convince that this change is necessary and can
improve the user experience in the Go language.

I think that the problems I raise in this post are painful to a lot of Go programmers,
and I could only hope that this post will result in an effort
towards a solution, or an inspiration for a better solution.

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

The **right** way is to update 98 functions.
Update each function to accept the context as it's first argument and
to call the next function in the stack with that context object:

```diff
 func f1(ctx context.Context) {
-  f2()
+  f2(ctx)
 }

-func f2() {
+func f2(ctx context.Context) {
-  f3()
+  f3(ctx)
 }

[ ... f3 through f98 ... ]

-func f99() {
+func f99(ctx context.Context) {
-  f100(context.TODO)
+  f100(ctx)
 }

 func f100(ctx context.Context) {
   <-ctx.Done()
 }
```

The **wrong** way is to store the context in a place which is globally available.
We'll elaborate on it later.

The proposed **right** solution works, but it has some drawbacks:

1. There is a high burden in updating all function calls to accept the context
   and to pass it following calls.
   All along the call stack.
2. Functions that have nothing to do with context, become aware for the context.
   It is messy, distracting and increase the risk to introduce new bugs.
3. Could lead to code duplication or increase in API surface.
   For example, the case of public API that should maintain backward compatibility.
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

   This pattern exists in the standard library where public functions
   had to adjust themselves to the context when it was introduced.
   For example: `net.Dial`/`net.DialContext` and `sql.Exec`/`sql.ExecContext`.

4. We can get stuck if somewhere in the middle of the call stack we don't have
   control on the code.
   In this situation, we can't use the context at all.

   For example,
   the very popular ORM library [GORM](https://github.com/jinzhu/gorm)
   still [does not support context](https://github.com/jinzhu/gorm/issues/1231).
   Since the context must be passed explicitly through the entire call stack,
   GORM users can't enjoy the benefits of using the context in SQL queries,
   even though that the `sql` package do support it.

The explicitness of the context is it's strength.
But, it does come with a price.
The current context system might cause high burden, distracting code,
high API exposure, backward compatibility issues and impossible implementations.

### 2. The Context Should not be Stored

The proposed "wrong" solution to the problem discussed in the previous chapter
was to store the context in a global place.

Let's discuss two wrong solutions:

- Use a global variable.

```diff
+var gCtx context.Context

 func f1(ctx context.Context) {
+  gCtx = ctx
   f2()
 }

 func f2() { f3() }

 [ ... f3 through f99 remain unchanged ... ]

-func f100(ctx context.Context) {
+func f100() {
-  <-ctx.Done()
+  <-gCtx.Done()
 }
```

This solution is very wrong.
For instance, it will fail for concurrency reasons.
We can't call `f1` from two different goroutines concurrently.
Concurrent calls to `f1` will override `gCtx`,
which will allow `f100` of the first call to read the context of the second call.

- Create a struct that will hold the context.

```diff
+type fs struct {ctx context.Context}

 func f1(ctx context.Context) {
-       f2()
+       f := fs{ctx: ctx}
+       f.f2()
 }

-func f2() { f3() }
+func (f *fs)f2() { f.f3() }

 [ ... f3 through f99 with the same change ... ]

-func f100(ctx context.Context) {
+func (f *fs)f100() {
-        <-ctx.Done()
+        <-f.ctx.Done()
 }
```

This is quite a big change, and most of the times it won't be as easy as
in the example above.
Gladly, this code is safe for concurrent usage.
On the other hand, this is also not a good solution,
let's understand why.

The `context` package documentation contains the following paragraph.
Please follow the paragraph citation and my wanderings about them.

> Programs that use Contexts should follow these rules to keep interfaces
> consistent across packages and enable static analysis tools to check
> context propagation:

We need to follow rules when using context.
We need to use linters to check our context propagation.
Are we using such tools?
[Apparently](https://github.com/golang/go/issues/16742), there is no such tool.

> Do not store Contexts inside a struct type; instead, pass a Context explicitly
> to each function that needs it.

This line instruct us to choose the first solution over the second solution.
It made me wander, why should there be rules about how to use the context object?

> The Context should be the first parameter, typically named ctx:
>
>     func DoSomething(ctx context.Context, arg Arg) error {
>             // ... use ctx ...
>     }

This is a convention. Which is OK.
But still, it is up to the programmer to be aware of it and to follow it.
This is very not Go-ish, very not similar to `go fmt` for example.

> Do not pass a nil Context, even if a function permits it.

Another rule, OK.
Again, the programmer needs to be aware of it.

> Pass `context.TODO` if you are unsure about which Context to use.

What does it mean?
How can I not be sure which context to use?
Specially with the current design where creating, modifying and passing the
context is so explicit?

Let's go back to the first part of the citation.
The simple rules that we must obey are:

1. Always pass the context by function calls (preferably always as first argument).
2. Store the context only in a function local variable.
3. Context value should never be nil.

And maybe a fourth rule, if the second one was not clear enough:
**never** store the context in any struct or global variable.

Those are strict rules.
Even the standard library itself find it hard to follow them.
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

This is technically violates the first rule of the context -
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
and included less API additions. Keeping the http package API clean as it used to be.
It only had to forego in violating the context rules and shallow copy
(with the `WithContext` method) of the request object whenever the context should be updated.

The current implementation of the context system encourages such foregoes.
The rules are strict and it is easy to disregard them when too many changes are committed.

We might also be thankful that this was the implementation chosen for the `http` package.
But should we also do the same in our own libraries?

Why is it so important to follow the context rules?
Let's examine the case of `http.Request`:

1. The request object becomes our context manager.
   Instead of using the context object, we usually find ourselves pass
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

2. If `http.Request` becomes the context, manager, updating the context becomes
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

In order to achieve the context powers, we must obey the rules.
The rules are strict so it is sometimes easy to workaround them.
This is usually done by storing the context, which may have bad implications.
The current design of the context system encourages such workarounds - and this is why
the rules were made up in the first place.

### 3. The Existence of `context.TODO`

We've met the `TODO` already.
The `TODO` is actually a "workaround", for the design of the current context system.
This is the documentation:

> TODO returns a non-nil, empty Context.
> Code should use `context.TODO` when it's unclear which Context to use or it is not yet
> available (because the surrounding function has not yet been extended to accept a
> Context parameter).
> TODO is recognized by static analysis tools that determine whether
> Contexts are propagated correctly in a program.

This comment actually states that the
existence of `context.TODO` ("should use `context.TODO` when")
is a proof for problems #2 ("sometimes unclear") and #1 ("not yet available").
If those problems did not exist, so `context.TODO` did not exist.

The parody in the `TODO` existence is that with all the explicitness that the context
package provides, it is still "unclear which Context to use or it is not yet available".

## Proposal

The proposal discusses the approach of storing the context in the goroutine struct,
referred as "**goroutine scoped context**".
We will see how it can solve all the enumerated problems, without any compromises.

Storing a context object in a "goroutine local storage"
(analogue to [thread-local storage](https://en.wikipedia.org/wiki/Thread-local_storage)),
was already discussed in Github issue
[#21355](https://github.com/golang/go/issues/21355).
The issue discussion had diverged from the original purpose,
and the proposal did not cover the essence of the given problem.
Eventually the issue was closed.
The reasons of which it was closed are not related to this proposed solution.

The proposal is composed of several required changes, which will define
the language API for goroutine scoped context.
After which, we will discuss the correctness of this new definitions.

### 1. Store a Context object in the Goroutine Struct

First we need to enable the storage of a context object in the goroutine struct.
We will assume it is possible and dismiss threats of cyclic dependencies
as "implementation details".

This stage goes hand in hand with a second stage:

### 2. Add Accessor functions Goroutine Context

The following goroutine context accessor functions should be added
to the `context` package:

```go
// Get gets the context of the current goroutine.
func Get() Context
// Set updates the context of the current goroutine.
func Set(ctx Context)
```

### 3. Update `go` to Propagate the Context

The context should propagate through goroutines.
The default behavior is that an invoked goroutine gets it's parent context.
When goroutine **A** is invoking a new goroutine **B**, **B** should get **A**'s context.

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

<!-- Furthermore, it goes hand by hand with the first change, in the direction of making
the context a first class citizen of the Go language, and not just another package
in the standard library. -->

If language syntax modification is a limitation here, see
[appendix I](#appendix-i---syntax-change-alternative).

### Philosophy

Now that we have defined the goroutine scoped context API,
we have the tools to wander about the essence of goroutine
scoped context:

#### "Should Goroutines Have a Context?"

Dave Chaney wrote a post about "Context isn't for cancellation"
[blog post](https://dave.cheney.net/2017/08/20/context-isnt-for-cancellation).
Even though I disagree with the main issue raised in this post,
Dave raises a good and valid point, the context object has two independent roles.
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
   This could replace the classic cancellation signalling by an empty-struct "done" channel,
   which is no longer needed.
   There is new, one, standard way to indicate if a a running code should be done.

2. **Values**: Custom key-value pairs that can be retrieved from the context.
   Inspected by the `Value` method and controlled by the `context.WithValue` modifier.

   Goroutine scoped context introduces a way to ask from any piece of code:
   "What is the value of 'X'?"

   This is delicate question, and has no unclear to me.
   Adding values to the goroutine context should be done
   only if all following code should know the value of "X".
   This is not always the case -
   For example, an HTTP middleware that extracts user credentials from the request
   and adds it to the goroutine context.
   Not necessarily all handler code should know about those credentials.

   But this applies to the current context design as well -
   Imagine the given example, just think of request context instead of goroutine context.

   Context values should not be abused and programmers should take good care
   when considering storing values in the context object.

   This proposal does not fix, change, or enhance this aspect of the context, but provides
   a way to obtain those values without explicitly passing the context object through
   a the call stack.

Adding the context accessor functions maintain the
explicitness of the previous context system.
One could follow exactly where the context has been set and has been used.
Additionally, since it does not need to be passed through function calls,
it prevents breaking APIs.
Finally, it depresses the need to store the context anywhere but a local variable,
and make the decision of choosing the context clear.

We've made arguments why the context should be goroutine scoped.
But let's examine why it should not be functioned scoped.

#### "Should Function Get a Context?"

We've enumerated several points for and against function scoped context.
But we haven't actually discussed the meaning.
Functions group lines of code that are invoked sequentially.
Having a unique context specific for those set of lines, have no additional
value, in any other case but for testing purposes.

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
but it discourage it.
A function should not get the context by argument, but by `context.Get()`.

### Conclusions

In this proposal it is claimed that the context object,
which is now function scoped, should be goroutine scoped.

This conception change prevents the need
to pass the context object explicitly through the call stack,
it eliminate the motivation to store the context anywhere but local variable,
and obviate the existence of `context.TODO`.

On the other hand, it maintains the essential code explicitness,
reduces code verbosity, reduces API exposure,
makes easier context adapting for existing code,
and not less important, maintains backward compatibility.

The proposed change makes the context object a first class citizen of Go.
It should be integrated into the goroutine struct and into the `go` keyword syntax.
The reason is that the context object provides go with missing capabilities
of controlling goroutine lifecycle, and storing scoped metadata information.

### Arguments Against this Proposal

I understand that this proposal might be seen as controversial for many Go developers.
Here are some opinions that might relate against the proposed change.

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

**Answer**: But actually, it is not the same.
In Go's error handling, a function returns an error only if it doesn't handle it.
But when dealing with context, a function should receive it in arguments and pass it through function calls, even if it is has no concern about the context.
Currently you are gratuitously forced to handle context.

Additionally, the Go team has understood that error handling is sometimes a burden,
and makes Go code clumsy.
One of Go 2 proposals deals exactly with this issue, with the name:
[error handling](https://go.googlesource.com/proposal/+/master/design/go2draft-error-handling-overview.md).
It is a time to understand that also context handling is sometimes a burden,
and makes Go code more clumsy.

#### Context is for Network Code

The context object is mainly used by the `net` package, and should
not penetrate the other parts of the language.

**Answer**: Even though `context` used to be `x/net/context`,
it is not anymore part of the `net` package.
Despite the fact that the `net` package is the main consumer,
it is also being used by packages like
`database/sql`, `os/exec`, `runtime/trace`, `runtime/pprof`, `cmd/vet` and more.

In this proposal I tried to emphasize the importance of the role that the context
can take in managing goroutine lifecycle,
in the general form, and not only in network context.

## Proof of Concept

Inspired by [a8m](https://github.com/a8m) idea,
I've implemented a simplified version of the proposed solution
without any changes to the standard library.
It is available on [github.com/posener/context](https://github.com/posener/context).

The purpose of this library is only to give a feeling how context in goroutines will be like,
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
context.Set(ctx)
// Goroutine context was updated, so: context.Get() == ctx
go func() {
  // New goroutine invoked with patent context: context.Get() == ctx
}()
f() // Inside f: context.Get() == ctx
```

## Appendices

### Appendix I - Syntax Change Alternative

An alternative for the `go ctx f()` syntax.

Another option is to add another function to the `context` package:

```go
func Go(ctx Context, f func()) {
  go func() {
    Set(ctx)
    f()
  }()
}
```

This function will run `f` in a new goroutine with the given `ctx`.
This solution is less preferred than changing the `go` keyword:
**(1)** Two not important function calls are added to the stack,
and **(2)** it limits the function signature to be `func()`,
so more complicated functions should be wrapped with a `func() {}`.

### Appendix II - Adopting New Conventions

First, new functions should not have the context as their first argument.
It is no longer needed.

```diff
-func f(ctx context.Context) {
+func f() {
+  ctx := context.Get()
}
```

Old functions that accept the context object should be deprecated:

```diff
+// Deprecated, use g instead.
func f(ctx context.Context) {
  // Use ctx...
}

+func g() {
+  ctx := context.Get()
+  f(ctx)
+}
```

New code that use old style, context accepting functions can simply
pass `context.Get()`:

```diff
-f(context.TODO())
+f(context.Get())
```