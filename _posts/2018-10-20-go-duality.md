---
layout: post
title: The Go Duality
keywords: go,golang,duality,channel,io,reader,writer
---

Suppose that you want to write a simple Go program:
A program that copies a file and stops and **cleans the copy** when
receiving an OS signal.
As it turns out, the solution is not obvious.
The reason is that the Go language contains two fundamental language entities
that can't interact with each other - "The Duality" (A name chosen by the author).

In this post I will present those entities,
the fundamental difference between them,
and the problems that it arises.

:heart: I would love to know what you think.
Please use the comments platform on the bottom of the page.

## The Duality Entities

Two of the fundamental entities of Go are **channels** and
the **IO interfaces** (`io.Reader` and `io.Writer`).
Both of those entities provide basic IO operations, but they behave in
completely different ways.
Worse, code uses one type of entity can't interact with code that
uses the other.

### Example

To better understand the difficulty,
lets consider the example given in the prologue:

> A program that copies a file and stops and **cleans the copy** when
> receiving an OS signal.

How would you implement it?

The following program copies the file and stops when receiving an OS signal.
However, it does not clean the copy, since it does not catch the signal.

```go
package main

import (
    "io"
    "log"
    "os"
)

func main() {
    if len(os.Args) < 2 {
        log.Fatal("Usage: must specify source and destination")
    }
    srcPath, dstPath := os.Args[1], os.Args[2]

    src, err := os.Open(srcPath)
    if err != nil {
        log.Fatalf("Failed open %q for read: %v", srcPath, err)
    }
    defer src.Close()

    dst, err := os.Create(dstPath)
    if err != nil {
        log.Fatalf("Failed creating %q: %v", dstPath, err)
    }
    defer dst.Close()

    _, err = io.Copy(dst, src)
    if err != nil {
        defer os.Remove(dstPath)
        log.Fatalf("Failed copy: %v", err)
    }
}
```

We can test this program:

```bash
$ # Create a large source file
$ # (will give us some time to interrupt the copy).
$ fallocate -l 10G src
$ # Invoke the program and interrupt (by pressing ctrl-C).
$ go run main.go src dst
^C
$ # The program exited on signal. Was the dst cleaned up?
$ ls dst --size --human-readable
572M dst
$ # The destination file is still there.
$ # The os.Remove was not called.
```

This means that we must [catch the signal](https://godoc.org/os/signal):

```diff
+   sig := make(chan os.Signal, 1)
+   signal.Notify(sig, os.Interrupt)

    _, err = io.Copy(dst, src)
```

Now we are stuck. We have the `src` which implements `io.Reader`,
the `dst` which implements `io.Writer` and `sig` which is a channel.
We want to copy from `src` to `dst` but cancel and delete `dst` if
a signal is sent in `sig`.
`io.Copy` is blocking, so we can't stop it from the same goroutine.

One of the options to overcome this obstacle is to divide
the long operation into shorter operations and to check
the signal status between them.

Change the `io.Copy` call:

```diff
-    _, err = io.Copy(dst, src)
+    _, err = chunkedCopy(sig, dst, src)
```

The `chunkedCopy` function:

```go
func chunkedCopy(sig <-chan os.Signal, w io.Writer, r io.Reader) error {
    const chunkSize = 1024
    for {
        select {
        case <-sig:
            return fmt.Errorf("interrupted")
        default:
            _, err := io.CopyN(w, r, chunkSize)
            if err != nil {
                return err
            }
        }
    }
}
```

Let's try again the program:

```bash
$ go run main.go src dst
^CFailed copy: interrupted
$ ls dst --size --human-readable
ls: cannot access 'dst': No such file or directory
```

The solution works, however, it is a workaround,
as any other possible solutions.
The reason is the duality in the Go language:
The synchronous IO copy operation can't be stopped,
the asynchronous cancellation can only happen
**between** synchronous operations.

To farther understand the duality,
let's first understand the different mechanisms and
their primary use cases.

## Understanding

### Channels

**Channels** are **"asynchronous"** IO mechanism.
They are mostly used for inter-goroutin communication, for timings,
and for cancellation.
For example, in the standard library, channels are use in the following APIs:

* [`context.Context`](https://golang.org/src/context/context.go#L97)-
  Has a `Done()` method that returns a channel. It is used for cancellation.
* [`time.Tick`](https://golang.org/pkg/time/#Tick),
  [`time.After`](https://golang.org/pkg/time/#After),
  [`time.Ticker.C`](https://golang.org/src/time/tick.go?s=12)-
  Provide a channel that is used for timing.
* [`os/signal.Notify`](https://golang.org/pkg/os/signal/#Notify)-
  Manipulate the channel such that will be used for cancellation.

### IO Interfaces

**IO interfaces** are **"synchronous"** IO mechanisms.
They are mostly used for IOs with external resources, such as files,
network and OS processes, and in-program buffers manipulation.
Some examples from the standard library:

* [`os.File`](https://godoc.org/os#File)-
  Implements all IO methods.
* [`bytes.Buffer`](https://golang.org/pkg/bytes/#Buffer)-
  Implements all IO methods.
* [`exec.Cmd`](https://godoc.org/os/exec#Cmd)- Has an `Stdin`
  field that is a `Reader`, and `Stdout` and `Stderr` which
  are `Writer`s.

A careful reader will find some network APIs missing in the list above.
These APIs were not forgotten, but are intentionally absent,
since these APIs were chosen to live on the boarder of the
duality of the Go language.

### The Standard Library Exceptions

Some components in the `net` package live on the
thin line of the duality.
They don't actually contain IO interfaces and channels,
since it is impossible.
But they do mix synchronous and asynchronous APIs.

On of them is the [`net.Conn`](https://golang.org/pkg/net/#Conn) interface.
On one hand, this interface has read and write methods.
And on the other hand it has `Set(Read|Write)?Deadline` methods.

A synchronous IO (read or write) operation from the connection can be interrupted
by asynchronous deadline which was set.

Another example is the
[`http.Request`](https://golang.org/pkg/net/http/#Request).
It has `Body` field which implements the read IO interface
(the synchronous part).
But also has `Context()` which returns the request's context
(which contains a channel, the asynchronous part).

A synchronous IO (read or write) of the request body,
can be asynchronously interrupted by the context which was set.

In those examples the calling any of the synchronous IO APIs,
might result in a (valid) error that is caused by the asynchronous
part of the same entity.

## Conclusions

Even though the use cases of the synchronous parts and the asynchronous
parts of the language is different,
it is not rare that code of one type needs to interact with code
of the other type.
However, the current language design does not provide an easy way
to handle this interaction.
Some components solve this problem by providing both synchronous
and asynchronous APIs, but most of the IO components in the language
miss the second type.

Some components solve this problem by exposing a method that accept
a context, such as: `net.DialContext`, `sql.QueryContext`.
To my opinion, this is quite a generic way to solve this problem,
and it is also cleaner than exposing `SetDeadline` methods.

There is still an open [Github issue](https://github.com/golang/go/issues/20280)
which proposes to add context to the IO interfaces, which is quite
interesting idea.

My [previous post](/context-scoping) could also provide an
interesting solution to this problem :smile:















<!-- ## Channels

From the [Go spec](https://golang.org/ref/spec#Channel_types):

> A channel provides a mechanism for concurrently executing functions
> to communicate by sending and receiving values of a specified element type.

### Properties

* **Direction**: A channel can be bidirectional, send (`chan<-`) or receive (`<-chan`).
* **Capacity**: A channel can have a capacity, which behaves like a buffer of items.

### State

* **Length**: An estimation about the number of elements that are currently in the channel.
* **Closed**: A channel can be either closed or not closed.
  Multi value receive (`elem, ok := <-c`) returns `ok == false` if the channel is closed.
  When a channel `c` is closed:
  * `close(c)` panics.
  * `c <- elem` panics.
  * `elem := <-c` returns zero value of the channel type.

## IO (Reader and Writer) Interfaces

In the standard library:

## Mixed types

* [`http.Response`](https://golang.org/pkg/net/http/#Response)-
  Has `Body` of type `io.ReadCloser`, and can use the request context.


  -->