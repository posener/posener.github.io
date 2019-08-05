---
layout: post
title: Inclusion; No-Go Files in a Go Program
keywords: go,golang,static,files,resources,assets,gitfs,webserver,filesystem,http.FileSystem,fsutil
github: https://github.com/posener/gitfs
---

Static files, also named assets or resources, are files that do not contain code, but used by the program. In Go, they are any non `.go` file. They are mostly used for web content such as HTML, javascript or images served by web servers, but they can be used by any program in the form of templates, configurations, images and so forth. The main problem is that these assets are not compiled with the source code. When developing a program, it is possible to access them from the local filesystem, but then, when the software is built and deployed, these files are not in the local filesystem anymore and we need to provide the program a way to access them. Go does not provide an out-of-the-box solution to this problem. This post will describe this problem, common solutions, and the approach taken in [gitfs](https://github.com/posener/gitfs) to handle it. A [bonus section](#fsutil) will explain some interesting aspects about the `http.FileSystem` interface.

:heart: I would love to know what you think. Please use the comments platform on the bottom of the post for discussion.

## The Problem

In many cases, Go programs need to access no-Go files. These files can be accessed through local filesystem when developing the program. For example, reading a file with the `os.Open` function uses the local filesystem. Many standard library functions use the local filesystem. For instance, the `http.Dir` function for serving files, or `template.ParseFiles` and `template.ParseGlob` for loading templates all work only with local filesystem.

Working with local filesystem in the development process is a seamless experience. The program is being run with `go run` or tested with `go test`, and the files are accessible in their path relative to the current working directory (CWD). The problem arises after the project is built (using `go build`) and the binary is deployed. Now the static files are not necessarily available at the same location, or even anywhere. In the following section we will discuss different solutions that enable the program access these files when deployed.

## Possible Solutions

Before diving into solutions in Go, lets see an approach taken in Python. Pip is the package manager for Python. Among many other features, it enables a program to define [`data_files`](https://docs.python.org/2/distutils/setupscript.html#installing-additional-files). These files are packed with the program, and installed in a location which will be accessible to the deployed program. The Python developer doesn't have to worry about the program environment. Whether it is development or production, if everything was configured correctly, the static files will be available.

Go's modules do not support packing static files. In Go, the most common solution is **binary-packing** or [**resource-embedding**](https://github.com/avelino/awesome-go#resource-embedding), like in the popular library [statik](https://github.com/rakyll/statik), [packr](https://github.com/gobuffalo/packr) by Buffalo, the good old and simple [go-bindata](https://github.com/go-bindata/go-bindata) and many more. As far as I know, in all these implementations, a CLI tool packs asset files into a Go file by encoding the file content and storing it in a generated Go file. This generated file provides an API to access the assets, and when the program is built, these files are compiled into the Go binary. Usually, the CLI command will be set by a `//go:generate` comment, such that the files will be generated any time `go generate` is invoked.

One advantage of this solution is safety - it does not matter if the Go code runs in development flow, in tests, or in production, it always uses the generated version of the static files content - same version and same content in any environment. However, this approach has several disadvantages. First, the development flow is cumbersome, especially when modifying the assets themselves. After every change we need to regenerate the files (with a `go generate` invocation) which can take precious time. Some of the tools have partial solutions to this problem, none of them is easy, intuitive or can be easily integrated with other Go tools or commands. Another drawback is that the static files content and their generated counterpart might diverge, as there is no guarantee that they were regenerated after every change. To overcome this drawback, we will need to add a special validation test in the CI flow - for example run `go generate` and verify an empty `git diff`. Lastly,  the commits that modify the static content are usually accompanied with an ugly diff of the generated files, or with an extra commit containing this diff.

Personally I found this flow inconvenient, and I mostly prefer a simpler and more primitive  solution: embed the static content in the Go files manually. This can be done by adding to required content to the Go files. For example:

```go
var tmpl = template.Must(template.New("tmpl").Parse(`
…
`))

const htmlContent = `
<html>
…
</html>
`
```

That solution works for small projects. But it also possesses several disadvantages as the static content, embedded in a Go file, is harder to edit and manage. First, you won't have any syntax highlighting since the editor/IDE is parsing the file as GO code. Second, syntax errors with line number will point on the line within the embedded text, which is not the line in the file. For example, if the template has an error, and the `template.Must(template.New("tmpl").Parse("..."))` panics, the error line number will be relative to the template text and not to the Go file. Lastly, it's much harder to embed binary content in this way.

Another possible solution is to have an external packing mechanism. For example, provide a docker container that contains the static files, or installable package, such as RPM, that stores the static files at a given location. This approach has several disadvantages - the need to have a docker daemon running, or packing differently for different OS distributions. But the main disadvantage is that the program is not self contained, and the way it runs in development and production is very different and hard to manage.

## gitfs

gitfs is a library that bridges over some of the flaws in the solutions mentioned above. It's designed to enable developers to run the code in development flow from local path, to quickly make changes to the static content and seamlessly run the same code in production, with the option not to use binary packing.

One of its design principles is **seamless transition** - a flag or environment variable that can change the way the program runs. This is achieved by using `http.FileSystem` which abstracts the type of the underlying filesystem. The implementation could be a local directory, files that are packed in a Go file or fetched from remote endpoint. For using static content, the developer should call `gitfs.New` which returns `http.FileSystem`. They then use this abstracted filesystem to read static content, regardless of the underlying implementation.

The next question is how the same path can be represented by the same location for local access or for a production system. The way that Go imports packages kind of answer this question. The form of domain and path, such as `github.com/user/project`, is universal representation of a path in a project. `gitfs` adopted this notation for definying a filesystem, so Go developers would feel comfortable with it. Any path within a project , or any specific branch or tag of the project, can be determined with the same principles. For example: `github.com/user/project/path@v1.2.3` represents the `github.com/user/project` github project at path `path` and tag `v1.2.3`.

Imagine a production system that accesses static content without binary packing. `gitfs` enables this by calling Github APIs in order to fetch the filesystem structure and the file content. When the program creates the filesystem it loads the structure from a Github API. The content itself can be fetched in two modes: lazily, only when accessed, or prefetching of all the content when the filesystem is loaded.

`gitfs` also enables binary-packing, but it delivers a smooth experience. First, the CLI tool that generates the packing Go code looks for all the calls for creating a filesystem using `gitfs.New`, so the user doesn't need to run the CLI with a specific filesystem, but it is automatically inferred. Then, it downloads all the required content and stores it in a generated Go file. This Go file registers the available content in an `init()` function. When the same `gitfs.New` call for creating a filesystem is called by the program, it checks for registered content and uses it rather than getting the content from remote repository if it is available. The result behavior is seamless - if the content is available from binary content, it will use the binary content. Otherwise, it will fetch it from the remote server.

As mentioned in the prologue, one of the drawbacks of generating binary content is the possibility for divergence between the static content and the packed content. If the developer changes the static content without running `go generate`, the program might not act as expected. The way that gitfs tackles this problem is to additionally generate a Go test file that simply loads and compares the generated content and the static content. If local changes were made without regenerating, the test will fail.

A cool anecdote is that the `gitfs` tool uses itself to binary-pack its own template files, and uses gitfs library to load them.

### Example

Let's look at an [example](https://github.com/posener/gitfs/blob/master/examples/templates/templates.go) that loads a template file with glob pattern from the `gitfs` repository:

```go
// Add debug mode environment variable. When running with
// `LOCAL_DEBUG=.`, the local git repository will be used
// instead of the remote github.
var localDebug = os.Getenv("LOCAL_DEBUG")

func main() {
	ctx := context.Background()
	// Open repository 'github.com/posener/gitfs' at path
	// 'examples/templates' with the local option from
	// environment variable.
	fs, err := gitfs.New(ctx,
		"github.com/posener/gitfs/examples/templates",
		gitfs.OptLocal(localDebug))
	if err != nil {
		log.Fatalf("Failed initializing git filesystem: %s.", err)
	}
	// Parse templates from the loaded filesystem using a glob
	// pattern.
	tmpls, err := fsutil.TmplParseGlob(fs, nil, "*.gotmpl")
	if err != nil {
		log.Fatalf("Failed parsing templates.")
	}
	// Execute a template according to its file name.
	tmpls.ExecuteTemplate(os.Stdout, "tmpl1.gotmpl", "Foo")
}
```

Running this code with `go run main.go` will load the template from Github, while running it with `LOCAL_DEBUG=. go run main.go` will load the local file.

## fsutil

The `http.FileSystem` is a simple interface that represents an abstract filesystem. It has a single method, `Open` that tags a path relative to the root of the filesystem, and returns an object that implements the `http.File` interface. This interface is a common interface for a file or a directory. Since it is heavily used by `gitfs`, the module contains the [`fsutil`](https://godoc.org/github.com/posener/gitfs/fsutil) package which provides useful tools for this interface.

The [`Walk`](https://godoc.org/github.com/posener/gitfs/fsutil#Walk) function, integrates the `http.FileSystem` interface with [`github.com/kr/fs.Walker`](https://godoc.org/github.com/kr/fs#Walker) which enables walking over all the filesystem files.

Go's standard library template loading functions work only on local filesystem. In `fsutil` you'll find a ported version that enables to use over any implementation of `http.FileSystem`. Use the [`fsuitl.TmplParse`](https://godoc.org/github.com/posener/gitfs/fsutil#TmplParse) instead of [`text/template.ParseFiles`](https://golang.org/pkg/text/template/#ParseFiles). [`fsuitl.TmplParseGlob`](https://godoc.org/github.com/posener/gitfs/fsutil#TmplParseGlob) instead of [`text/template.ParseGlob`](https://golang.org/pkg/text/template/#ParseGlob). And their HTML counterpart: [`fsutil.TmplParseHTML`](https://godoc.org/github.com/posener/gitfs/fsutil#TmplParseHTML) instead of [`html/template.ParseFiles`](https://golang.org/pkg/html/template/#ParseFiles) and [`fsutil.TmplParseGlobHTML`](https://godoc.org/github.com/posener/gitfs/fsutil#TmplParseGlobHTML) instead of [`html/template.ParseGlob`](https://golang.org/pkg/html/template/#ParseGlob).

The [`Glob`](https://godoc.org/github.com/posener/gitfs/fsutil#Glob) function takes a `http.FileSystem` and a list of glob patterns and returns a filesystem that contains only the files that agree with the given glob patterns.

The [`Diff`](https://godoc.org/github.com/posener/gitfs/fsutil#Diff) function calculates filesystem structure differences and content differences between two filesystem.

If you have more ideas for such utility functions, please step forward and [open an issue](https://github.com/posener/gitfs/issues).

## Conclusions

No-Go files currently need special treatment in Go. In this blog I tried to present the challenges, the currently available solutions and how `gitfs` makes using static files easy. We've learned about the http.FileSystem interface, and its powers of abstracting filesystem operations. Last thought; I wonder if there is a room for a built-in treatment for static files by the new Go modules system.
