---
layout: post
title: Function Failure Reporting - Error or OK
keywords: go,golang,function,error,ok
reddit: https://www.reddit.com/r/golang/comments/6qyomu/function_failure_reporting_error_or_ok/
gist: https://gist.github.com/posener/a303becac35835ad7bf5e15fe061893e
---

Go's ["multiple return values"](https://golang.org/doc/effective_go.html#multiple-returns)
feature, can be used for several purposes. Among them for failure reporting to the function caller.
Go has two conventions for failure reporting, but currently, no clear convention for which to use when.
I've encountered different programmers that prefer different choices in different cases.
In this article, we will discuss the two, and try to make the process of choosing our next function signature
more conscious.

## The Basics

Let's introduce the two failure reporting conventions.

### Error

It is common to see a function signature that returns an error, like `os.Chdir(dir string) error`,
or a pair of value and error, like `os.Open(name string) (*File, error)`.
A function that returns such a value, actually says: "I can't handle what just happened, you handle it".
Usually, when a called function has such a signature, a gopher will check the error value
and handle it.

```go
f, err := os.Open("my-file.txt")
if err != nil {
  // handle error
}
// use f
```

This is one of the nicest things in Go! The error handling is explicit, clear, and done in an 
["indent error flow"](https://github.com/golang/go/wiki/CodeReviewComments#indent-error-flow).
A nice article about how a gopher should handle errors can be found in
[Dave Chaney's blog](https://dave.cheney.net/2016/04/27/dont-just-check-errors-handle-them-gracefully).
My favorite part in the article is "Only handle errors once".

### OK bool

Another way to report the caller about a failure, is to return a bool, or a pair of a value and a bool, Like
`http.ParseHTTPVersion(vers string) (major, minor int, ok bool)`.
By convention, such a function will use [named return values](https://tour.golang.org/basics/7).
The last returned value in the function signature will be called `ok` of type `bool` and will indicate
if the function failed.
When a called function has such signature, a gopher will check the `ok` value after the call:

```go
minor, major, ok := http.ParseHTTPVersion("HTTP/1.1")
if !ok {
  // handle failure
}
// use minor and major
```

Here again, the handling of the failure is very clear, and is done in an indented block as well.

## I'm Confused

I am about to write a new function, what will be its signature?

If the function is guaranteed to complete successfully, and this is either by having no way
to fail, or by handling failures in it, there is no reason to return either an error or an OK bool.
But what if the function can fail, and its scope can't deal with that failure? as previously discussed,
we have two options here. Let's consider them carefully.

When my function is very simple, I can use the OK bool. It can fail, but when it
fails, the caller knows why. Good examples from the go language are not function calls - but language syntax,
which use the OK `bool` convention:

1. The interface assertion: `val, ok := foo.(Bar)`, if the `ok` value is `false`, 
it is clear that `foo` is not of type `Bar`, we don't have any other option here.
2. The map's key testing: `val, ok := m[key]`, if `ok` is `false`, it is clear to the caller that
the key is not in the map.

An example that demonstrates the downside of such signature is the
[implementation of the ParseHTTPVersion function](https://golang.org/src/net/http/request.go?s=22614:22676#L687).
The function returns a `false` value in 4 places, so at least 4 different inputs can result in a `false` value
due to different reasons. The caller has no information about the failure, just the fact that it happened.

On the other hand, when opening a file, there could be many reasons for failure, the file might not exist,
the user might not have permissions for the file, and so on,
and this is why [`os.Open`](https://golang.org/pkg/os/#Open) returns a file object and an `error` pair.
In case of a failure, the returned object in the `error` interface will contain the reason, and the caller
can understand how he could handle the failure.

We can come to the straightforward conclusion that returning an `error` is more informative.
A value that implements the `error` interface, can be called with its `Error()` function
and a string that represents the error will appear to the perplexed gopher.

Additionally, we can say that the group of functions that OK `bool` can be used
as the failure indicator is a subset of the group of functions that `error` can be used as their
failure indicator. In any case where an OK bool is chosen, it can be replaced with an `error` interface.
But not the other way around, if we replace an `error` with OK `bool`, we loose information,
and the caller could not handle all the cases he could before.

Popularity: A simple grep on the standard library (not too accurate) shows that there are
about 7991 functions that use the `error` interface as a return argument,
and about 236 functions that use a last returned argument named `ok` of type `bool`.

## APIs

Your functions are your APIs. And as we all know, we shall not break them. Even the breaking of internal functions
that are used widely in your package can result in painful code refactoring. The function's API consists of its name,
its arguments, and the return values.
Assuming you are writing a very simple function, that might fail, and because it is so simple, you ought to
give it an OK `bool` return value. A very simple indication of success that makes elegant `if`-statements after
the function call.
In most cases that would be a wise decision, in terms of APIs.

But in some "border" cases of functions that are not as simple as they first seem, more logic is needed
to be injected into the function, and more failure cases are introduced. Still, at every failure case it will
`return false`, assuming we are not willing to break API.
The calling function, that might log the failure, will have no choice, but to notify that `error: 'foo' failed`.
which will result in a program that is much harder to debug. If the calling function is trying to handle the failure,
it might handle some cases in a wrong way, just because it didn't get all the information.

Using the `error` interface, is much more flexible. Since it is an interface, you can return anything that implements
it, and any caller will know what to do, and will have more information about what exactly failed in your function.

## The Interface Cost

`error` is an interface, which has a performance penalty over a `bool` variable. This performance
penalty can be considered minor, depending on the function purpose. This might be a good reason to
prefer an OK `bool` return type. An interesting debate about interfaces performance can be found
[here](https://groups.google.com/forum/#!topic/golang-nuts/7tUShPuPfNM).

## Messy code

When some functions return `error` as a failure indicator, and some return an OK `bool`, 
a function that is a bit complex and uses several function calls can look a bit ugly:

```go
a, err := foo()
if err != nil {
  log.Println("foo failed:", err)
}
b, ok := bar() 
if !ok {
  log.Println("bar failed")
}
err := baz()
if err != nil {
  log.Println("baz failed:", err)
}
```

## Conclusions

In this article, I propose making conscious decisions in selecting functions failure reporting type.
It would be awesome to have good guidelines or conventions for the failure indicator right return type.

As **I** can see it, and in **my** opinion, the default choice for failure indication should be the `error` interface.
It is explicit, flexible, and can be used everywhere - even where you might want to use the OK `bool` type.

Guidelines to prefer an OK `bool` over `error`:

1. It is very very very clear what `ok == false` means.
2. It is performance critical to prefer `bool` over `error`.

I would love to hear your opinions about this subject. If you agree, disagree, or have in mind more aspects of
this problem, please comment below.