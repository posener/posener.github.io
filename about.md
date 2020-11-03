---
layout: page
title: About
permalink: /about/
keywords: posener,about
---

* Software developer at Google.
* Former software developer at Stratoscale.
* Former mechanical engineer.

## Creations Repertoire

I love building things on my free time.
Here are a few open source projects I've been working on.

### [complete](https://github.com/posener/complete/tree/master)

> Bash completion written in go + bash completion for go command.

My most popular creation, mainly because it is used by [hashicorp](https://github.com/hashicorp) in
some of their products. It enables a go binary to bash-complete itself (or other binary). All the
completion logic is done in Go code. The way it works is that when the completion is needed, the
same binary runs with special environment variables, and it then functions as completion logic for
the shell.

A bonus package in this project is [`gocomplete`](https://github.com/posener/complete/tree/master/gocomplete)
which is bash completion for the Go command line, written in Go.

### [goaction](https://github.com/posener/goaction)

> Write Github Actions in Go.

A library that helps writing Github Actions using the Go programming language. It enables writing a
standard Go script that can be run locally as well as a Github Action.

Additionally, the library provides
[statically typed Github Actions API](https://pkg.go.dev/github.com/posener/goaction#pkg-variables),
and a [Github API client for the repository](https://pkg.go.dev/github.com/posener/goaction@v0.1.4/actionutil#Client).
The mind-blowing (inceptional) part is that this repository is also a Go Github Action. It
automatically creates and updates all the boilerplate required for converting a Go repository to a
Github Action.

Back in the days, I've created the [goreadme project](#goreadme). It was originally developed as a
[Github App](https://github.com/posener/goreadme-server) that used to be hosted on Heroku. Besides
the complex structure, an additional issue was that users were afraid to give the App credentials to
their repository. Once the Github Actions was introduced, I simplified the project significantly by
converting it from a Github App to a Github Action. Since it was written in Go, I thought that it
would be cool to take the opportunity and create a general infrastructure for creating Github
Actions in Go, and this is where the goaction came from.

Github [wrote a blog post](https://github.blog/2020-10-29-github-action-hero-eyal-posener-and-go-action)
and [twitted](https://twitter.com/github/status/1322297320290066432) about it.

### [gitfs](https://github.com/posener/gitfs)

> A complete solution for static files in Go code.

I thought it would be nice to be able to import static file without the burden of `go generate`
command any time they are changed. In this project I'm using mostly Github APIs to get static files
the program wants to open. The usage is as simple as:

```go
fs, err := gitfs.New("github.com/user/repo/path@version")
// Handle err…
f, err := fs.Open("file.txt")
// Handle err and use f.
```

One of the nice things here is that the `fs` object is an implementation of the standard
`http.FileSystem` interface.

I then extended the library to be able to load the files from local directory for development
purposes. And then extended it to convert the filesystem to be contained in a Go file that enables
binary packing of the filesystem. Transiting from either of these modes is automatic.

This library also contains some `http.FileSystem` goodies in the
[fsutil](https://github.com/posener/gitfs/tree/master/fsutil) package, which enable walking over the
files in the filesystem and loading Go templates from them - they can be used with any
implementation of `http.FileSystem`.

### [h2conn](https://github.com/posener/h2conn)

> HTTP2 client-server full-duplex connection.

A wrapper around Go's standard http2 functions, that provide a simple reader and writer interfaces
for using both on the server side and the client side.

### [wstest](https://github.com/posener/wstest)

> Go websocket client for unit testing of a websocket handler.

If you have a Gorilla websocket handler, and want to test it without starting the server (similar to
the http testing in Go), this package is for you.

### [orm](https://github.com/posener/orm)

> Go Typed ORM.

I was working with [gorm](https://github.com/jinzhu/gorm), and got frustrated about the abundance of
type safety. In this project I was trying to create an ORM that generates type-safe go code for
accessing databases. It works great, but not production ready.

### [Stratoscale/logserver](https://github.com/Stratoscale/logserver)

> Web log viewer that combines logs from several sources

A hackathon project that was developed to a useful product.
In Stratoscale, our product was a distributed system that ran on multiple servers.
We had services that were logging to a local storage, and they could run on each server, several
servers, or a single server. If something went wrong, you would want to check any of the server to
see if the service ran there in the time of the failure and then could read what went wrong in the
logs. This task was OK if there were a few nodes, but when there were tens of them, it became
impossible only to understand where to look for the logs.

In this project, we created a service that connects to all the nodes and provides a single merged
directory web view of all of them. For each in the files in the directory tree it shows on which
nodes the file is located, and enables you to read and search in the logs.

### [Stratoscale/swagger](https://github.com/Stratoscale/swagger)

An extension of [go-swagger](https://github.com/go-swagger/go-swagger) with custom templates. I was
working on this at Stratoscale when we've start standardizing our Go services. After a while I
helped merging its content to go-swagger as a
[contrib option](https://github.com/go-swagger/go-swagger/tree/94886a08ebe16708d905b36452d457d7a69b907f/generator/templates/contrib/stratoscale).

### [goreadme](https://github.com/posener/goreadme)

> Update readme.md from go doc.

Command line tool that loads the documentation of a Go package and generates a markdown file that
can be used as `README.md`.

There is also an open-source service that generates README files automatically for Github projects.
Here is the [code](https://github.com/posener/goreadme-server), and here it is live:
[https://goreadme.herokuapp.com](https://goreadme.herokuapp.com).

### [client-timing](https://github.com/posener/client-timing)

> An HTTP client for [go-server-timing](https://github.com/mitchellh/go-server-timing) middleware.

The go-server-timing middleware is very cool. It adds timing details to response headers (Instead of
sending them to an external service) and it is a standard web header, so web browsers knows to plot
it nicely. This timing details can tell how much time took each part of creating the response
(calling database, calling other service, etc…)

This small addition that I provide enables automatic timing propagation through http calls between
servers. So when service A calls service B which calls service C, The headers will be joined such
that whoever called A will get the full details of the whole stack.

### [cmd](https://github.com/posener/cmd)

> A minimalistic library that enables sub commands with the standard `flag` library.

The standard flag library is a great library for adding support for flag parsing for binaries.
It has clean API and easy to use. However, when using it, it is not trivial to add a sub commands
for the main command. Most programs have sub commands, for example, the `go` command have sub
commands such as `go run`, `go build` or `go test`.

The `cmd` library adds support for sub commands in a way that retains the look and feel of the
standard `flag` library. It also enables automatic bash completion, flag value enforcement,
positional argument definition and enforcement and automatic usage.

Check out the [example](https://github.com/posener/cmd/blob/master/example/main.go).

### [order](https://github.com/posener/order)

> Enables easier ordering and comparison tasks

This package provides functionality to easily define and apply order on values. It works out of the
box for most primitive types and their pointer versions, and enable order of any object using
three-way comparison with a given `func(T, T) int` function, or by implementing the generic
interface: `func (T) Compare(T)` int.

Read more about it in the [blog post](/order).

### [script](https://github.com/posener/script)

> Easily write scripts with Go. Improvements for https://github.com/bitfield/script.

I went across the really cool library https://github.com/bitfield/script which helps writing scripts
in Go. Writing scripts in Go may result in quite verbose code, and the standard library does not
provide all the required tooling around it (mainly because it is not intended to). This tool enables
running short and clear scripts in Go, imitating the piping features of shell commands.

For example: `numErrors, err := script.File("test.txt").Match("Error").CountLines()` reads a file,
filters only for lines with the word "Error" and return the number of lines.

I really liked the library and took a deeper look into the implementation. One thing that I poped
out was that the piping is done by reading all the data from a previous command into the memory and
manipulating it there, not as shell pipes work, or as piping should be handled. For example, in the
above example, we can read each line from the file. Then, in the match function, process each line
and pass on only matching lines. Then, in the count lines we can just store a counter and not even
store the line data. To perform the above pipe, we only need memory that the largest line can fit
into (actually not even that). We certainly not need memory that is large enough to fit the
"test.txt" file.

I came up with an improvement that takes advantage of Go's `io.Reader` interface. There are two
building blocks:

The [`Command`](https://github.com/posener/script/blob/master/command.go) struct, which represent a
single command in the stream. It can be read by the exposed `io.Reader`, and can be optionally
closed with `io.Closer`. Opposed to shell commands, the `Command` do not have an `stderr` output,
but uses Go errors to report when an error occurs. As in shell commands, having error does not
necessarily result in no output from the command - a command can have output and an error.

The [`Stream`](https://github.com/posener/script/blob/master/stream.go) struct enables chaining
commands one to another. There are some factory methods that create streams from different inputs
such as `Stdin`, `Cat` that streams file content, `Ls` that lists files, or so forth. The stream can
be chain using different commands, such as `Grep` to filter for a regexp, `Head` to get the
beginning or the ending of the stream, `Cut` to take certain fields of each line, `Sort`, `Uniq` or
so forth. Then, the stream can be dumped to different writers, such as `ToStdout`, `ToFile`,
`ToString` or so forth. These methods also return to the users all the errors that occured in all
the commands in the stream.

Another way to process the stream is the the
[`Exec`](https://github.com/posener/script/blob/master/exec.go) command which got special attention.
It enables running a shell command, which can take the stream as its `stdin`, and continue the
stream with the program `stdout`. If the program fails, its stdout still continue to the stream, but
an error will be added (just as shell commands do). If the user is interested in the program's
`stderr`, it can provide an extra writer.

A custom command can be used using the `Stream`'s `PipeTo` method. This method gets a function that
given a `io.Reader`, representing the stdin for the command, returns a `Command`. This way a user
can define a custom command to interact with the stream.

### [tiler](https://github.com/posener/tiler)

> A Go port of https://github.com/nuno-faria/tiler.

Tiles an image from a set of given small images.

### [chrome-github-godoc](https://github.com/posener/chrome-github-godoc)

> Chrome extension that replaces Github view of git commit messages with useful godoc.org synopsis.

I found the github last-commit synopsis very unuseful when I look on a repository on Github. I
thought it would be nice to replace it with the godoc synopsis in case it is a Go package.
You can download it from the [chrome extensions webstore](https://chrome.google.com/webstore/detail/github-godoc/fhlenghekakdnaamlbkhhnnhdlpfpfej).

### [fcontext](https://github.com/posener/fcontext)

> Context implementation with (pseudo) constant access-time.

Since the standard library context value is implemented as a tree, the search of the value is going
in all the nodes to the root of the tree (the `context.Background()` node). This is O(height of
tree). This implementation provides best case O(1) lookup time, with worst case as the standard
implementation. The challenging part is that nodes can only know about values stored in the nodes
between them and the root, but not on any other node. This implementation is also fully compatible
with the standard library context.

As a result of this project, I updated a related Github issue in the Go language
([Issue #28728](https://github.com/golang/go/issues/28728)) to "enable first class citizenship of
third party implementations", with a proposal about how to improve the cooperation of the standard
library with third party implementations. The proposal was declined, but Russ Cox came up with an
elegant solution that actually solved the discussed problem
([Commit](https://github.com/golang/go/commit/0ad36867)).

### [contexttest](https://github.com/posener/contexttest)

Test package for context implementations.

One of the results of the [`fcontext`](#fcontext) package was the creation of a standard library to
test context implementations. The context is an interface, which can have any underlying
implementation. This library checks that the implementation does what it is expected of.

### [ctxutil](https://github.com/posener/ctxutil)

> A collection of context utility functions.

Some functions that I missed when I use contexts.

### [posener/context](https://github.com/posener/context)

> A proof of concept implementation of scoped context, following my blog post
> [Goroutine Scoped Context Proposal](https://posener.github.io/goroutine-scoped-context).

### [tarfs](https://github.com/posener/tarfs)

> An implementation of the FileSystem interface for tar files.

### [flag](https://github.com/posener/flag)

> Like the flag package, but with bash completion support!

A small package that extends the API of the standard `flag` package, but with bash completion
enabled.

### [sharedsecret](https://github.com/posener/sharedsecret)

Implementation of [Shamir's Secret Sharing](https://en.wikipedia.org/wiki/Shamir's_Secret_Sharing)
algorithm.

### [fuzzing](https://github.com/posener/fuzzing)

A package that enables easy fuzzing with [go-fuzz](https://github.com/dvyukov/go-fuzz). Go-fuzz
invokes Fuzz functions with a sequence of bytes that should explore the space of inputs. In many
cases this sequence of bytes should be converted to other objects as input to the tested function.
This library helps with the conversion. See the
[example](https://github.com/posener/fuzzing/blob/master/example_fuzz.go) to understand how to use
it.

### [ps1](https://github.com/posener/ps1)

> A lightweight script that sets a nice shell prompt (similar to powershell, but fast).

Like the flag package, but with bash completion support!

### [eztables](https://github.com/posener/eztables)

> iptables in web browser

### [githubapp](https://github.com/posener/githubapp)

> Oauth2 Github-App authentication client
