---
layout: post
title: Be Careful with Table Driven Tests and t.Parallel()
---

We Gophers, love table-driven-tests, it makes our unit-testing structured, and makes it easy to add different
test cases with ease.

Let’s create our table driven test, for convenience, I chose to use `t.Log` as the test function.
Notice that we don't have any assertion in this test, it is not needed to for the demonstration.

```go
func TestTLog(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		value int
	}{
		{name: "test 1", value: 1},
		{name: "test 2", value: 2},
		{name: "test 3", value: 3},
		{name: "test 4", value: 4},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			// Here you test tc.value against a test function.
			// Let's use t.Log as our test function :-)
			t.Log(tc.value)
		})
	}
}
```

The output of running such a test file will be:

```bash
 $ go test -v ./...
=== RUN   TestTLog
=== RUN   TestTLog/test_1
=== RUN   TestTLog/test_2
=== RUN   TestTLog/test_3
=== RUN   TestTLog/test_4
--- PASS: TestTLog (0.00s)
    --- PASS: TestTLog/test_1 (0.00s)
    	test_test.go:19: 1
    --- PASS: TestTLog/test_2 (0.00s)
    	test_test.go:19: 2
    --- PASS: TestTLog/test_3 (0.00s)
    	test_test.go:19: 3
    --- PASS: TestTLog/test_4 (0.00s)
    	test_test.go:19: 4
PASS
ok  	github.com/posener/testparallel	0.002s
```

As can be seen, go has the `t.Run()` function, which creates a nested test inside an 
existing test. This is useful:

* We can see each test case individually in the output,
* we can know exactly which test case failed in case of failure
* and we can run a specific test case using the `-run` flag: `go test ./... -v -run TestTLog/test_4`.

Having this separation in a table driven test makes It very tempting to add some more parallelism to our testing.
This could be done by adding `t.Parallel()` to the nested test created by `t.Run()`:

```diff
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
+			t.Parallel()
			// Here you test tc.value against a test function.
			// Let's use t.Log as our test function :-)
			t.Log(tc.value)
		})
	}
}
```

This is the result:

```bash
$ go test -v ./...
=== RUN   TestTLog
=== RUN   TestTLog/test_1
=== RUN   TestTLog/test_2
=== RUN   TestTLog/test_3
=== RUN   TestTLog/test_4
--- PASS: TestTLog (0.00s)
    --- PASS: TestTLog/test_1 (0.00s)
    	test_test.go:20: 4
    --- PASS: TestTLog/test_3 (0.00s)
    	test_test.go:20: 4
    --- PASS: TestTLog/test_2 (0.00s)
    	test_test.go:20: 4
    --- PASS: TestTLog/test_4 (0.00s)
    	test_test.go:20: 4
PASS
ok  	github.com/posener/testparallel	0.002s
```

Easy right? The test passed! well, yes. But we were lucky enough to run it with the `-v` flag which turns on the logs,
and we see that the logs might be a bit surprising.

As it can be seen from the test output: in all the cases, our test function `t.Log` was called with the same argument:
 `4` in all 4 test cases. That's not what we wanted, and different than what was tested without the `t.Parallel()` call.

*Notice that even if we did have an assertion in this test, the test run would still pass - but only one of the test
 cases was checked! Without logging the argument and actually checking the log output of the test we would think that 
 all our test cases were checked and that our function is great. This is very dangerous and could lead to bugs in our
  code!*

# What Happened?

An experience Gopher will immediately sense the source for the problem. A less experience one might fight this issue
 for hours, or, in case that he was lucky and saw the bug when adding the `t.Parallel`, will just give up and remove
  the added line.

This is a well known Go gotcha, well hidden inside the go testing framework. This is what happen when using a closure
 is inside a goroutine. Actually, this bug is so common, that it is the first paragraph in the
  [Go common mistakes guide](https://github.com/golang/go/wiki/CommonMistakes#using-goroutines-on-loop-iterator-variables)
   in the github go wiki.
In our case, we have the `func(t *testing.T) {...}` closure, that is ran in a go routine invoked inside the `t.Run()`
 function. When calling `t.Parallel()` the test sends a signal to its parent test to stop waiting for it, and then the
  loops continues.

This causing the `tc` variable to advance to the next `tests` value, which causes the "Go common mistake" to happen.

# How to Solve This?

There are some solutions to this problem. None of them is too elegant. The easiest, maybe not nicest, is to define a new
 local variable inside the loop that will hide the loop variable.

To make our life easier, and maybe more confusing, we can name it with the same name of the loop variable (Thanks @a8m):

```diff
	for _, tc := range tests {
+		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			// Here you test tc.value against a test function.
			// Let's use t.Log as our test function :-)
			t.Log(tc.value)
		})
	}
}
```

Running the test in the above code will result in the right tests, notice that the order of the output have changed since
 we are not running the test serially anymore.

```bash
$ go test -v ./...
=== RUN   TestTLog
=== RUN   TestTLog/test_1
=== RUN   TestTLog/test_2
=== RUN   TestTLog/test_3
=== RUN   TestTLog/test_4
--- PASS: TestTLog (0.00s)
    --- PASS: TestTLog/test_1 (0.00s)
    	test_test.go:23: 1
    --- PASS: TestTLog/test_2 (0.00s)
    	test_test.go:23: 2
    --- PASS: TestTLog/test_4 (0.00s)
    	test_test.go:23: 4
    --- PASS: TestTLog/test_3 (0.00s)
    	test_test.go:23: 3
PASS
ok  	github.com/posener/testparallel	0.002s
```

# Final Thoughts

I think that this issue can be very dangerous - the coverage of a function can change from full cover to only one test
 case without even noticing it.

This “common mistake” issue is pretty disturbing and catches often even experienced Go programmers. In my opinion,
 it is one of the things that we might want to either: 

* change in the language,
* or have a linter for (Maybe in `vet`, now that is running as part of go test in v1.10).

This was first published through [gists](https://gist.github.com/posener/92a55c4cd441fc5e5e85f27bca008721).
