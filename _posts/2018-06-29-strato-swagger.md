---
layout: post
title: Swagger with Go Part 3 - Stratoscale/swagger
---

In the [previous post](/go-swagger), I gave an intro for [go-swagger](https://github.com/go-swagger/go-swagger), 
a tool that generates Go code from swagger files. In this post, we will see Stratoscale's version of go-swagger, 
available as [open source](https://github.com/Stratoscale/swagger).

## Into

Stratoscale's swagger is a **slightly** modified go-swagger. It takes advantage of the fact that swagger expose a
flag to run it with custom templates. Those template files are the one that are being used to generate the Go code. 
Not all of the files can be modified - but it is a good thing - if you change less things, you can easily upgrade
go-swagger versions, which include bug fixes and improvements.

## Usage

Since Stratoscale's version is using the actual `swagger` command, just with custom template files, we found that
the easiest way to run it, is with a docker container.
It is also one of the way to run swagger from the
[go-swagger install docs](https://github.com/go-swagger/go-swagger/blob/master/docs/install.md).

I personally prefer to run the tool from a docker container and not with downloaded binaries - This
is easier in the scripts and build systems - once you have docker running on a given machine, you don't need to install
anything else and scripts just work (If the image does not exists, the docker engine will pull it automatically).

It assumes that your project is in the `GOPATH` and you are currently in the directory that has
a `swagger.yaml` file. It also uses a version in the container tag - I like to keep my scripts consistent and control
the version I am using, so the generated code won't suddenly change after running the script. 

To create a command `swagger`, we can create a bash alias with the following code:

```bash
$ alias swagger='docker run --rm -e GOPATH=${GOPATH}:/go -v $(pwd):$(pwd) -w $(pwd) -u $(id -u):$(id -u) stratoscale/swagger:v1.0.14'
```

> Check out the [Docker Hub tags page](https://hub.docker.com/r/stratoscale/swagger/tags) for the latest version

To test that it works:

```bash
$ swagger version
version: 0.14.0
commit: 25e637c5028dee7baf8cdf5d172ccb28cb8e5c3e
```

You can add the alias command line to your `~/.bashrc` file in order to make it available any time you get a bash shell.

### Features

#### Improved Server Template

As described in the [previous post](/go-swagger/#1-painful-configure_go), one of the week points in go-swagger, to my
opinion, is the generated `restapi/configure_*.go` file, that is autogenerated only once on the first time.

We took inspiration from the [protobuf](https://github.com/golang/protobuf) Go implementation - When you run a server,
The generated code takes an object that should implement the service functionality.

Our solution was to modified the `restapi/configure_*.go` file. We introduced a number of changes, described below:

##### 1. Always Generated

Our configure file is re-generated every time `swagger` is called, and it should not be modified.

##### 2. Expose http.Handler

As described in the [previous post](/go-swagger/#3-hard-to-get-an-httphandler), `go-swagger` gives a fully functional
server command. But customizing it is hard, and specially getting the `http.Handler` to run with your own code.

Our `restapi` package exposes an `restapi.Handler` function, that should be called with `restapi.Config` struct.
This struct contains the configuration of the server - the managers that implement all the server functionality ([see
next section](#3.-expose-service-interfaces)).

The function returns an `http.Handler` that can be used as you wish - wrap it with middlewares and serve it with
whatever go server you like.

##### 3. Expose Service Interfaces

We added interfaces section, that are exposed from the `restapi` package. Each `swagger` tag is exposed through
a `<tag-name>API` interface, and contains all the operations that belong to this tag.

Using tags to categorize operations is a common methodology in the Open API auto generated code, also is also
the practice in `go-swagger`. This enables the user separate different logic entities in the server, we call those
logical entities "managers".

In the [example](https://github.com/Stratoscale/swagger/blob/master/example/restapi/configure_swagger_petstore.go#L31)
we can see the exposed `PetAPI` and `StoreAPI` interfaces. Here is the `PetAPI` interface:

```go
type PetAPI interface {
	PetCreate(ctx context.Context, params pet.PetCreateParams) middleware.Responder
	PetDelete(ctx context.Context, params pet.PetDeleteParams) middleware.Responder
	PetGet(ctx context.Context, params pet.PetGetParams) middleware.Responder
	PetList(ctx context.Context, params pet.PetListParams) middleware.Responder
	PetUpdate(ctx context.Context, params pet.PetUpdateParams) middleware.Responder
}
```

Those interfaces are defined as fields in the `restapi.Config` struct that configures the server `http.Handler`.
This enables testing the http handler routing and middleware without actually invoking the business logic.
In the example [main_test.go](https://github.com/Stratoscale/swagger/blob/master/example/main_test.go), the http handler
is configured with mocked "managers".

It also enables the "managers" encapsulated, they only implement the interface and can be tested separately.

##### 4. Usage of context.Context

The way go-swagger injects authentication tokens to the operation function is by adding a second argument called
`principal`, which is also, not that documented.

Our generated operation functions receive a `context.Context` as their first argument. This context will be in runtime
the incoming request context. Instead of passing the principal object as an argument to the operation function we use
the context object with the `restapi.AuthKey` key.

This context also can be used with middlewares - they can inject values to the context and read it when necessary
in the operation function body.

Take care not to abuse the context function, and use it only for "contextual" data.

#### Improved Client Template

As described in the [previous post](https://posener.github.io/go-swagger/#4-hard-to-consume-and-to-customize-generated-client),
the go-swagger generated client code is hard to consume, customize and it exposes non-standard options.
We decided to change it's template too, and introduce the following changes:

##### 1. Creating a New Client

We changed the client "generator" signature to be only a `client.New` function, that returns a new client, and it
receives a `client.Config` with optional customizable fields:

1. URL (of standard type `*url.URL`) - set client to a custom endpoint, the default one is the endpoint that is set in 
   the swagger file.
2. Transport (of standard type `http.RoundTripper`) - To enable custom client side middlewares, such as authentication, 
   logging, tracing etc.
   
##### 2. Expose Client Interfaces

Exposing interfaces for clients is important. It makes the consumption of such client easier.
The AWS SDK is a good example for that, each service exposes a client and an interface that implement
the client methods.
For example, here is the [`ec2.New()`](https://github.com/aws/aws-sdk-go/blob/master/service/ec2/service.go#L47), 
function that returns an `*ec2.EC2` object - the client with the EC2 API. But the SDK also includes the package 
`ec2iface` with the [`ec2iface.EC2API`](https://github.com/aws/aws-sdk-go/blob/master/service/ec2/ec2iface/interface.go#L62)
which is just the interface that the same client implements.

Why does it make it easy to consume? Your code can accept the interface and not the struct itself. then, in testings,
you can pass a mock object and test that the right calls where made and not make actual calls to AWS.

For example:

```go
func MyFunc(client ec2iface.EC2API) {
	resp, err := client.RunInstances(&ec2.RunInstanceInput{...})
	[...]
}
```

Then, your main will call it as `MyFunc(ec2.New(awsSession))`, but your test will call it as `MyFunc(&ec2Mock)`.

> Generating a mock to this API can be done easily with [mockery](https://github.com/vektra/mockery).
> The way I do it is by adding a gen.go in the root directory of my project. This file contains lines like
> 
> ```go
> //go:generate mockery -name EC2 -dir ./vendor/github.com/aws/aws-sdk-go/service/ec2/ec2iface -output ./mocks`
> ```
> Assuming you are vendoring your dependencies, after running `go generate` a file `./mocks/EC2API.go` containing
> a [testify's Mock](https://github.com/stretchr/testify#mock-package) for the EC2API interface should be created.

Back to go-swagger.

go-swagger generates a client object for each service tag. For example, the pet-store client contains two fields
for the pet-store services:

```go
type SwaggerPetstore struct {
	Pet       *pet.Client
	Store     *store.Client
    ...
}
```

Each of those services is defined on it's own package. We added to each package an `API` interface, which defines
the service functionality and should be used similarly to what described above. For example, the `client/pet` package 
now contains the following interface:

```go
type API interface {
	// PetCreate adds a new pet to the store
	PetCreate(ctx context.Context, params *PetCreateParams) (*PetCreateCreated, error)
	// PetDelete deletes a pet
	PetDelete(ctx context.Context, params *PetDeleteParams) (*PetDeleteNoContent, error)
	// PetGet gets pet by it s ID
	PetGet(ctx context.Context, params *PetGetParams) (*PetGetOK, error)
	// PetList lists pets
	PetList(ctx context.Context, params *PetListParams) (*PetListOK, error)
	// PetUpdate updates an existing pet
	PetUpdate(ctx context.Context, params *PetUpdateParams) (*PetUpdateCreated, error)
}
```

Additionally, we generate with mockery the struct `MockAPI` which is a mock for the `API` interface. So it could be 
used in tests without the need to generate it by the consumer.

### Example

We will go over the [example in the github repository](https://github.com/Stratoscale/swagger/tree/master/example)

#### . Testings

In the [main_test.go](https://github.com/Stratoscale/swagger/blob/master/example/main_test.go) we can see
testing of the http handler with mocking of all the "managers".
Those tests specially the expected behavior for authentication and authorization
since all the business logic is being mocked.