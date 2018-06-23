---
layout: post
title: Swagger with Go Part 2 - go-swagger
---

In the [previous post](/openapi-intro), I gave a short intro to the open API (Swagger) specification, and showed
some tooling around it.
In this post, I will elaborate on go-swagger, a tool that generates Go code from swagger files.

## go-swagger - Code Generation from Swagger

[go-swagger](https://github.com/go-swagger/go-swagger) is a tool for go developers to generate go code from
swagger files. It uses various libraries from thr [go-openapi github organization](https://github.com/go-openapi)
to handle the swagger specification and swagger files.

I've been following the project for a while now. It has a very high pulse, with commits being merged to master
branch on a daily basis. The main contributors are very responsive for issues :clap: .
It comes with versioned releases, and provide binaries or a docker container for it's command line tool.

## Example

First, follow the [docs](https://github.com/go-swagger/go-swagger/blob/master/docs/install.md) to install
the `swagger` command.
In this example we'll use the [`swagger.yaml` from the previous post](/openapi-intro#example).

### Generating a Server

Follow the bash commands below to see how to generate and run a Go server from a swagger file.
The only requirements for this to work is to have a `swagger.yaml` in
the current working directory, and that this directory will be somewhere inside the `GOPATH`.

```bash
$ # Validate the swagger file
$ swagger validate ./swagger.yaml
The swagger spec at "./swagger.yaml" is valid against swagger specification 2.0
$ # Generate server code
$ swagger generate server
$ # go get dependencies, alternatively you can use `dep init` or `dep ensure` to fix the dependencies.
$ go get -u ./...
$ # The structure of the generated code
$ tree -L 1
.
├── cmd
├── Makefile
├── models
├── restapi
└── swagger.yaml
$ # Run the server in a background process
$ go run cmd/minimal-pet-store-example-server/main.go --port 8080 &
  09:40:12 Serving minimal pet store example at http://127.0.0.1:8080
$ # go-swagger serves the swagger scheme on /swagger.json path:
$ curl -s http://127.0.0.1:8080/swagger.json | head
  {
    "consumes": [
      "application/json"
    ],
    "produces": [
      "application/json"
    ],
    "schemes": [
      "http"
    ],
$ # Test list pets
$ curl -i http://127.0.0.1:8080/api/pets
HTTP/1.1 501 Not Implemented
Content-Type: application/json
Content-Length: 50

"operation pet.List has not yet been implemented"
$ # Test enforcement of scheme - create a pet without a required property name.
$ curl -i http://127.0.0.1:8080/api/pets \
    -H 'content-type: application/json' \
    -d '{"kind":"cat"}'
HTTP/1.1 422 Unprocessable Entity
Content-Type: application/json
Content-Length: 49

{"code":602,"message":"name in body is required"}
```

Sweet stuff, and without doing anything! go-swagger generated several directories:

* `cmd` - Server `main()` function, flag parsing, server configuration and running the server.
* `restapi` - Routing logic from `paths` section in swagger file.
* `models` -  Models from `definitions` section in swagger file.

### Generating a Client

Let's check out the client

```bash
$ swagger generate client
```

And create a small program that uses the generated client in `main.go`

```go
package main

import (
	"context"
	"flag"
	"fmt"
	"log"

	"github.com/posener/swagger-example/client"
	"github.com/posener/swagger-example/client/pet"
)

var kind = flag.String("kind", "", "filter by kind")

func main() {
	flag.Parse()
	c := client.Default
	params := &pet.ListParams{Context: context.Background()}
	if *kind != "" {
		params.Kind = kind
	}
	pets, err := c.Pet.List(params)
	if err != nil {
		log.Fatal(err)
	}
	for _, p := range pets.Payload {
		fmt.Printf("\t%d Kind=%v Name=%v\n", p.ID, p.Kind, *p.Name)
	}
}
```

When running it, we get the expected 501 error:

```bash
$ go run main.go 
  15:57:53 unknown error (status 501): {resp:0xc4204c2000}
exit status 1
```

### Implement a method

As you can see, the auto generated go code returns 501 status code (not implemented HTTP error) for all the routes we defined.
Implementing what I like to call "business logic" of the generated server is done in the
`restapi/configure_minimal_pet_store_example.go` file.
This file is auto-generated, and it is unique - it will not be overwritten in a following invocation of a
`generate server` command.
As go-swagger suggest, you are allowed, and you should modify this file. It is created once - only when it does not
exist.

For the sake of the example, let's implement the pet list operation.

In the file we find this piece of code:

```go
func configureAPI(api *operations.MinimalPetStoreExampleAPI) http.Handler {
	[...]
	api.PetListHandler = pet.ListHandlerFunc(func(params pet.ListParams) middleware.Responder {
		return middleware.NotImplemented("operation pet.List has not yet been implemented")
	})
	[...]
}
```

As expected, the auto-generated code returns `middleware.NotImplemented`, implementing the `middleware.Responder`
interface - which is similar in many ways to the `http.ResponseWriter` interface:

```go
// Responder is an interface for types to implement
// when they want to be considered for writing HTTP responses
type Responder interface {
	WriteResponse(http.ResponseWriter, runtime.Producer)
}
```

For our convenience, the generated code includes responses for every operation that we defined in the `swagger.yaml` file.
Let's return a fixed list of pets for that API, and filter it by kind if the kind keyword was given in the query string.

```go
var petList = []*models.Pet{
	{ID: 0, Name: swag.String("Bobby"), Kind: "dog"},
	{ID: 1, Name: swag.String("Lola"), Kind: "cat"},
	{ID: 2, Name: swag.String("Bella"), Kind: "dog"},
	{ID: 3, Name: swag.String("Maggie"), Kind: "cat"},
}

func configureAPI(api *operations.MinimalPetStoreExampleAPI) http.Handler {
	[...]
	api.PetListHandler = pet.ListHandlerFunc(func(params pet.ListParams) middleware.Responder {
		if params.Kind == nil {
			return pet.NewListOK().WithPayload(petList)
		}
		var pets []*models.Pet
		for _, pet := range petList {
			if *params.Kind == pet.Kind {
				pets = append(pets, pet)
			}
		}
		return pet.NewListOK().WithPayload(pets)
	})
	[...]
}
```

Rerun the server, and test it with the client code:

```bash
$ go run main.go 
    0 Kind=dog Name=Bobby
    1 Kind=cat Name=Lola
    2 Kind=dog Name=Bella
    3 Kind=cat Name=Maggie
$ go run main.go -kind=dog
    0 Kind=dog Name=Bobby
    2 Kind=dog Name=Bella
```

## Things that can be Improved

Here I listed several things that I think need to be improved.
I want to emphasize that this is **my opinion**, and I think that dealing with them can make
 **the already great** go-swagger superb.

### 1. Painful `configure_*.go`

The `restapi/configure_*.go` file, showed [above](#implement-a-method), feels kind of hackey:
 * It is an autogenerated file, that is generated only if not exists - a pretty weired behavior.
 * When API is changed/added, manual manipulation is needed in this autogenerated file.
 * All the API resources are managed in the same file.
 * Last but not least, it is **impossible to have "dependency injection" to test the behavior** .

### 2. Required Fields

In the model definitions, required fields are generated as pointers, and optional fields are generated as values.
Foe example, the `Pet` model in the example with a required field `Name` and an optional field `Kind` and `ID`,
is generated as follows (The `readonly` property is yet to be supported):

```go
type Pet struct {
	ID   int64   `json:"id,omitempty"`
	Kind string  `json:"kind,omitempty"`
	Name *string `json:"name"`
}
```

The reason for this, as far as I understand, is to guarantee that the required field was actually passed.
In the AWS Go SDK a similar approach is taken, [but for optional fields](https://github.com/aws/aws-sdk-go/issues/114).
But this approach has it's disadvantages:

* Optional fields: If I get a Pet with `Kind == ""`, how can I know if it is an empty string or was not given at all? 
* Not fun to use: assigning and reading pointer variables can be painful, and many times helper functions are
  needed. The [`swag`](https://github.com/go-openapi/swag) package is a helper package to make the usage easier.
  
### 3. Hard to Get an `http.Handler`

The go-swagger generates a full server, with a main function and command line arguments which makes
a very fast 0-to-serve flow. It's really nice, but sometimes we might have our own main function, and it's own framework that includes environment variables, logging, tracing, etc. In this situation, Go has a standard `http.Handler` that I would expect the autogenerated
code will expose.
It is not that easy to get this handler with the current design of go-swagger.

### 4. Hard to Consume and to Customize Generated Client

The generated client works out of the box - as demonstrated in the example [above](#generating-a-client).
Nevertheless, customizing the client is hard, mainly due to the fact that it uses non-standard entities.
For example, the client has a `SetTransport` method, which accepts a go-swagger's `runtime.ClientTransport`.
Setting a new transport with customized HTTP client or custom URL is not a trivial task.

Another issue is that the client **lacks interfaces**. When I write a package that uses a client, I need an interface
for the client so I can mock it in the package's unit tests. The generated client does not provide such interface.
 
### 5. Not using standard `time.Time`

For various reasons, a field that is defiend as `type: string, format: date-time` is of format `strfmt.DateTime`
of the `github.com/go-openapi/strfmt` package and not `time.Time`.
This sometimes requires tedious type conversion when working with other libraries which expect the standard `time.Time`.

### 6. Versioning of go-openapi libraries

The go-openapi libraries are not versioned and unfortunately they occasionally they break the API.

## Stay Tuned

In the next post, I'll show a more go-ish flavor of go-swagger we developed in Stratoscale for our own services.
It uses the fact that go-swagger enables defining custom templates for some of the generated files,
and helped us overcome some of the difficulties we had with the go-swagger implementation.
