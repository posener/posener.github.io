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

### [complete](https://github.com/posener/complete)

> Bash completion written in go + bash completion for go command.

My most popular creation, mainly because it is used by [hashicorp](https://github.com/hashicorp) in some of their products. It enables a go binary to bash-complete itself (or other binary). All the completion logic is done in Go code. The way it works is that when the completion is needed, the same binary runs with special environment variables, and it then functions as completion logic for the shell.

A bonus package in this project is [`gocomplete`](https://github.com/posener/complete/tree/master/gocomplete) which is bash completion for the Go command line, written in Go.

### [gitfs](https://github.com/posener/gitfs)

> A complete solution for static files in Go code.

I thought it would be nice to be able to import static file without the burden of `go generate` command any time they are changed. In this project I'm using mostly Github APIs to get static files the program wants to open. The usage is as simple as:

```go
fs, err := gitfs.New("github.com/user/repo/path@version")
// Handle err…
f, err := fs.Open("file.txt")
// Handle err and use f.
```

One of the nice things here is that the `fs` object is an implementation of the standard `http.FileSystem` interface.

I then extended the library to be able to load the files from local directory for development purposes. And then extended it to convert the filesystem to be contained in a Go file that enables binary packing of the filesystem. Transiting from either of these modes is automatic.

This library also contains some `http.FileSystem` goodies in the [fsutil](https://github.com/posener/gitfs/tree/master/fsutil) package, which enable walking over the files in the filesystem and loading Go templates from them - they can be used with any implementation of `http.FileSystem`.

### [h2conn](https://github.com/posener/h2conn)

> HTTP2 client-server full-duplex connection.

A wrapper around Go's standard http2 functions, that provide a simple reader and writer interfaces for using both on the server side and the client side.

### [wstest](https://github.com/posener/wstest)

> Go websocket client for unit testing of a websocket handler.

If you have a Gorilla websocket handler, and want to test it without starting the server (similar to the http testing in Go), this package is for you.

### [orm](https://github.com/posener/orm)

> Go Typed ORM.

I was working with [gorm](https://github.com/jinzhu/gorm), and got frustrated about the abundance of type safety. In this project I was trying to create an ORM that generates type-safe go code for accessing databases. It works great, but not production ready.

### [goreadme](https://github.com/posener/goreadme)

> Update readme.md from go doc.

Command line tool that loads the documentation of a Go package and generates a markdown file that can be used as `README.md`.

There is also an open-source service that generates README files automatically for Github projects. Here is the [code](https://github.com/posener/goreadme-server), and here it is live: [https://goreadme.herokuapp.com](https://goreadme.herokuapp.com).

### [client-timing](https://github.com/posener/client-timing)

> An HTTP client for [go-server-timing](https://github.com/mitchellh/go-server-timing) middleware.

The go-server-timing middleware is very cool. It adds timing details to response headers (Instead of sending them to an external service) and it is a standard web header, so web browsers knows to plot it nicely. This timing details can tell how much time took each part of creating the response (calling database, calling other service, etc…)

This small addition that I provide enables automatic timing propagation through http calls between servers. So when service A calls service B which calls service C, The headers will be joined such that whoever called A will get the full details of the whole stack. 

### [chrome-github-godoc](https://github.com/posener/chrome-github-godoc) 

> Chrome extension that replaces Github view of git commit messages with useful godoc.org synopsis.

I found the github last-commit synopsis very unuseful when I look on a repository on Github. I thought it would be nice to replace it with the godoc synopsis in case it is a Go package.
You can download it from the [chrome extensions webstore](https://chrome.google.com/webstore/detail/github-godoc/fhlenghekakdnaamlbkhhnnhdlpfpfej).

### [fcontext](https://github.com/posener/fcontext)

> Context implementation with (pseudo) constant access-time.

Since the standard library context value is implemented as a tree, the search of the value is going in all the nodes to the root of the tree (the `context.Background()` node). This is O(height of tree). This implementation provides best case O(1) lookup time, with worst case as the standard implementation. The challenging part is that nodes can only know about values stored in the nodes between them and the root, but not on any other node.
This implementation is also fully compatible with the standard library context.

### [contexttest](https://github.com/posener/contexttest)

Test package for context implementations.

If you have a context implementation and you want to test that it provides the same behavior as the standard library context, you can use this package in order to test it.

### [ctxutil](https://github.com/posener/ctxutil)

> A collection of context utility functions.

Some functions that I missed when I use contexts.

### [posener/context](https://github.com/posener/context)

> A proof of concept implementation of scoped context, following my blog post [Goroutine Scoped Context Proposal](https://posener.github.io/goroutine-scoped-context).

### [tarfs](https://github.com/posener/tarfs)

> An implementation of the FileSystem interface for tar files.

### [flag](https://github.com/posener/flag)

> Like the flag package, but with bash completion support!

A small package that extends the API of the standard `flag` package, but with bash completion enabled.

### [ps1](https://github.com/posener/ps1)

> A lightweight script that sets a nice shell prompt (similar to powershell, but fast).

Like the flag package, but with bash completion support!

### [Stratoscale/swagger](https://github.com/Stratoscale/swagger)

An extension of [go-swagger](https://github.com/go-swagger/go-swagger) with custom templates. I was working on this at Stratoscale when we've start standardizing our Go services. After a while I helped merging its content to go-swagger as a [contrib option](https://github.com/go-swagger/go-swagger/tree/94886a08ebe16708d905b36452d457d7a69b907f/generator/templates/contrib/stratoscale).

### [eztables](https://github.com/posener/eztables)

> iptables in web browser

### [githubapp](https://github.com/posener/githubapp)

> Oauth2 Github-App authentication client
