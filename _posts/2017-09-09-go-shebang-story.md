---
layout: post
title: A Story About Writing Scripts with Go
---

This is a story about how I tried to use Go for scripting. 
In this story, I’ll discuss the need for a Go script, how we would expect it to behave and the possible implementations;
During the discussion I’ll deep dive to scripts, shells, and shebangs.
Finally, we’ll discuss solutions that will make Go scripts work.


## Why Go is good for scripting?

While python and bash are popular scripting languages, C, C++ and Java are not used for scripts at all, and some 
languages are somewhere in between.

Go is very good for a lot of purposes, from writing web servers, to process management, and some say even systems.
In the following article, I argue, that in addition to all these, Go can be used, easily, to write scripts.

What makes Go good for scripts?

- Go is simple,readable, and not too verbose. This makes the scripts easy to maintain, and relatively short.
- Go has many libraries, for all sorts of uses. This makes the script short and robust, assuming the libraries are 
stable and tested.
- If most of my code is written in Go, I prefer to use Go for my scripts as well. When a lot of people are collaborating 
code, it is easier if they all have full control over the languages, even for the scripts.

## Go is 99% There Already

As a matter of fact, you can already write scripts in Go.
Using Go’s  `run` subcommand: if you have a script named `my-script.go`, you can simply run it with `go run my-script.go`.

I think that the `go run` command, needs a bit more attention in this stage. Let’s elaborate about it a bit more.

What makes Go different from bash or python is that bash and python are interpreters - they execute the script while 
they read it.
On the other hand, when you type `go run`, Go compiles the Go program, and then runs it.
The fact that the Go compile time is so short, makes it look like it was interpreted.
it is worth mentioning “they” say “`go run` is just a toy", but if you want scripts, and you love Go, this toy is 
what you want.


## So we are good, right?

We can write the script, and run it with the `go run` command! What’s the problem?
The problem is that I'm lazy, and when I run my script I want to type `./my-script.go` and not `go run my-script.go`.

Let’s discuss a simple script that has two interactions with the shell:
it gets an input from the command line, and sets the exit code.
Those are not all the possible interactions (you also have environment variables, signals, stdin, stdout and stderr), 
but two problematic ones with shell scripts.

The script writes “Hello”, and the first argument in the command line, and exits with the code 42:
```go
package main

import (
    "fmt"
    "os"
)

func main() {
    fmt.Println("Hello", os.Args[1])
    os.Exit(42)
}
```

The go run command behaves a bit weird:

```bash
$ go run example.go world
Hello world
exit status 42
$ echo $?
1
```

We’ll discuss that later on.

The `go build` can be used. This is how you would run it using the `go build` command:

```bash
$ go build
$ ./example world
Hello world
$ echo $?
42
```

Current workflow with this script looks like this:

```bash
$ vim ./example.go
$ go build
$ ./example.go world
Hi world
$ vim ./example.go
$ go build
$ ./example.go world
Bye world
```

What I want to achieve, is to run the script like this:

```bash
$ chmod +x example.go
$ ./example.go world
Hello world
$ echo $?
42
```

And the workflow I would like to have is this:

```bash
$ vim ./example.go
$ ./example.go world
Hi world
$ vim ./example.go
$ ./example.go world
Bye world
```

Sounds easy, right?


## The Shebang

Unix-like systems support the [Shebang](https://en.wikipedia.org/wiki/Shebang_(Unix)) line.
A shebang is a line that tells the shell what interpreter to use to run the script.
You set the shebang line according to the language that you wrote your script in.

It is also common to use the [`env`](http://www.gnu.org/software/coreutils/manual/html_node/env-invocation.html#env-invocation)
command as the script runner, and then an absolute path to the interpreter command is not necessary.
For example: `#! /usr/bin/env python` to run the python interpreter with the script. 
For example: if a script named `example.py` has the above shebang line, and it is executable 
(you executed `chmod +x example.py`), then by running it in the shell with the command `./example.py arg1 arg2`, 
the shell will see the shebang line, and starts this chain reaction:

The shell runs `/usr/bin/env python example.py arg1 arg2`. This is actually the shebang line plus the script name
plus the extra arguments.
The command invokes `/usr/bin/env` with the arguments: `/usr/bin/env python example.py arg1 arg2`.
The `env` command invokes `python` with `python example.py arg1 arg2` arguments
`python` runs the `example.py` script with `example.py arg1 arg2` arguments.

Let’s start by trying to add a shebang to our go script.

### 1. First Naive Attempt:

Let's start with a naive shebang that tries to run `go run` on that script. After
adding the shebang line, our script will look like this:

```go
#! /usr/bin/env go run
package main

import (
    "fmt"
    "os"
)

func main() {
    fmt.Println("Hello", os.Args[1])
    os.Exit(42)
}
```

Trying to run it results in:

Output:
```bash
$ ./example.go
/usr/bin/env: ‘go run’: No such file or directory
```

What happened?

The shebang mechanism sends "go run" as one argument to the `env` command as one argument, and there is no such command,
typing `which “go run”` will result in a similar error.

### 2. Second Attempt:

A possible solution could be to put `#! /usr/local/go/bin/go run` as the shebang line.
Before we try it out, you can already spot a problem: the go binary is not located in this location in all environments,
so our script will be less compatible with
different go installations.
Another solution is to use `alias gorun="go run"`, and then change the shebang to `#! /usr/bin/env gorun`, in this case
we will need to put the alias in every system that we run this script.

Output:
```bash
$ ./example.go
package main:
example.go:1:1: illegal character U+0023 '#'
```

Explanation:

OK, I have good news and bad news, what do you want to hear first? We’ll start with the good news :-)

- The good news are that it worked, `go run` command was invoked with our script
- The bad news: the hash sign. In a lot of languages the shebang line is ignored as it starts with
a comment line indicator. Go compiler fails to read the file, since the line starts with an "illegal character"

### 3. The Workaround:

When no shebang line is present, different shells will fallback to different interpreters. Bash will fallback to run
the script with itself, zsh for example, will fallback to sh.
This leaves us with a workaround, as also mentioned in
[StackOverflow](https://stackoverflow.com/questions/7707178/whats-the-appropriate-go-shebang-line).

Since `//` is a comment in Go, and since we can run `/usr/bin/env` with `//usr/bin/env` (`//` == `/` in a path string),
we could set the first line to:

`//usr/bin/env go run "$0" "$@"`

Result:
```bash
$ ./example.go world
Hi world
exit status 42
./test.go: line 2: package: command not found
./test.go: line 4: syntax error near unexpected token `newline'
./test.go: line 4: `import ('
$ echo $?
2
```

Explanation:

We are getting close: we see the output but we have some errors and the status code is not correct.
Let's see what happened here.
As we said, bash did not meet any shebang, and chose to run the script as `bash ./example.go world` (this will result
in the same output if you'll try it).
That's interesting - running a go file with bash :-) Next, bash reads the first line
of the script, and ran the command: `/usr/bin/env go run ./example.go world`. "$0"
Stands for the first argument and is always the name of the file that we ran. "$@" stands for all the command line arguments.
In this case they were translated to `world`, to make: `./example.go world`.
That's great: the script ran with the right command line arguments, and gave the right output.

We also see a weird line that reads: "exit status 42". What is this?
If we would try the command ourselves we will understand:

```bash
$ go run ./example.go world
Hello world
exit status 42
$ echo $?
1
```

It is stderr written by the `go run` command. Go run masks the exit code of the script and returns code 1.
For further discussion about this behavior read here
[Github issue](https://github.com/golang/go/issues/17813).

OK, so what are the other lines? This is bash trying to understand go, and it isn’t doing very well.

### 4. Workaround Improvement:

[This StackOverflow page](https://stackoverflow.com/questions/7707178/whats-the-appropriate-go-shebang-line) suggests
to add `;exit "$?" to the shebang line. this will tell the bash interpreter not to
continue to the following lines.

Using the shebang line:

`//usr/bin/env go run "$0" "$@"; exit "$?"`

Result:
```bash
$ ./test.go world
Hi world
exit status 42
$ echo $?
1
```

Almost there: what happened here is that bash ran the script using the `go run` command,
and immediately after, exited with the go run exit code.

Further bash scripting in the shebang line, for sure can remove the stderr
"exit status" message, even parse it, and return it as the program exit code.

However:

- Further bash scripting means longer, and exhausting shebang line, which is supposed
to look as simple as `#! /usr/bin/env go`.
- Lets remember that this is a hack, and I don't like that this is a hack.
After all, we wanted to use the shebang mechanism - Why? Because it's simple, standard and elegant!
- That’s more or less the point where I stop using bash, and start using more comfortable
languages as my scripting languages (such as Go :-) ).

# Lucky Us, We Have [`gorun`](https://github.com/erning/gorun)


`gorun` does exactly what we wanted. You put it in the shebang line as `#! /usr/bin/env gorun`, and make the script
executable. That’s it, You can run it from your shell, just as we wanted!


```bash
$ ./example.go world
Hello world
$ echo $?
42
```

Sweet!

### The Caveat: Comparability


Go fails compilation when it meets the shebang line (as we saw before).

```bash
$ go run example.go
package main:
example.go:1:1: illegal character U+0023 '#'
```

Those two options can’t live together. We must choose:

- Put the shebang and run the script with `./example.go`.
- Or, remove the shebang and run the script with `go run ./example.go`.

You can’t have both!


Another issue, is that when the script lies in a go package that you compile. The compiler will meet this go file,
even though it is not part of the files that are needed to be loaded by the program, and will fail the compilation.
A workaround for that problem is to remove the `.go` suffix, but then you can’t enjoy tools such as `go fmt`.

# Final Thoughts

We’ve seen the importance of enabling writing scripts in Go, and we’ve found different ways to run them. 
Here is a summary of the findings:

| Type | Exit Code | Executable | Compilable | Standard |
|------|-----------|------------|------------|----------|
| `go run` | ✘     | ✘          | ✔          | ✔        |
| `gorun`  | ✔     | ✔          | ✘          | ✘        |
| `//` Workaround | ✘ | ✔       | ✔          | ✔        |

Explanation:
Type: how we chose to run the script.
Exit code: after running the script it will exit with the script’s exit code.
Executable: the script can be `chmod +x`.
Compilable: the script passes `go build`
Standard: the script doesn’t need anything beside the standard library.

As it seems, there is no perfect solution, and I don’t see why we shouldn’t have one.
It seems like the easiest, and least problematic way to run Go scripts is by using the `go run` command.
It is still too ‘verbose’ to my opinion, and can’t be “executable”, and the exit code is incorrect, which makes it hard
to tell if the script was completed successfully.

This is why I think there is still work do be done in this area of the language.
I don’t see any harm in changing the language to ignore the shebang line.
This will solve the execution issue, but a change like this probably won't be accepted by the Go community.

My colleague brought to my attention the fact that the shebang line is also illegal in javascript. But, in node JS,
they added a [strip shebang](https://github.com/nodejs/node/blob/master/lib/internal/module.js#L48) function which 
enables running node scripts from the shell.

It would be even nicer, if `gorun` could come as part of the standard tooling, such as `gofmt` and `godoc`.

### This was first published through [gists](https://gist.github.com/posener/73ffd326d88483df6b1cb66e8ed1e0bd).
