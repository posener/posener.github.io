---
layout: post
title: Open API with Go Part 1 - Introduction
keywords: go,golang,rest,swagger,open-api,open,api,http,server,microservice
---

In Stratoscale, after the standard transition from a monolith to micro-services, we discovered that an "API first"
approach with swagger was a good comfortable place you want to be.

In this series of three blog posts, I will **discuss Open API**, then I'll **show a go code generation tool called
go-swagger** and lastly I'll **describe our own flavor of go-swagger** and why we chose it.

## Open API ##

Open API, originally known as Swagger, is DSL (domain specific language) for describing REST APIs. It can be written in
either JSON or YAML.
The swagger standard is now on it's 3rd version, developed by *Open API Initiative*, an open source collaborative 
project of the Linux Foundation.

The go-to website is [swagger.io](https://swagger.io). Open API has many ecosystems and [tools](https://swagger.io/tools/)
developed around it, great [documentation](https://swagger.io/docs) and as far as I understand, the de-facto
standard in defining REST APIs (see [alternatives](#alternatives) below).

Developing REST services with open API dictates a certain methodology - a good methodology. First the API of the service
is defined, and only then, everything around it is constructed. There are many tools to help you do it right, which will
be described [below](#tools). The tools can be categorized as follows:

* Editors - Create/Edit swagger files.
* Generating clients in almost any language - with verification of request parameters.
* Generating servers in almost any language - with automatic verification of incoming requests, and outgoing responses.
* Mock servers from swagger files for testing purposes.
* Auto generation of CLI.

## Develop in High Scale

There are usually three parties concerened when a service is being developed: The architect(s), the service owner(s) and the service
consumer(s). When there are many players on the field, each one likes a ball in different color or shape, some play 
defence, some offense and some coordinate. Open API can help, and enable development in a high scale manner:

* Collaboration - all parties fully understand what is being developed. How it will integrate, what it is being expected
  to do, and how it will behave.
  
* Consistency - a client generated from a swagger file will know to talk to a server generated from the same file.
  
* Concurrency - Using tools around the swagger specifications, the owner and the consumer can work independently,
  and even test independently and meet only in integration stage for final tests of their implementations.
  
  The owner can test use a generated server and implement only business logic, and use a generated client and CLI to test it.
  
  The consumer can use an autogenerated client and a mock server for testings.
  
* Adaptability - APIs can be easily changed using re-generation of the code.

* Reflectivity - the server has a defined endpoint which can be documented to the service customers.

* Language Agnostic - even though the server is implemented in a specific language, consumers can be in any language,
  and clients / SDKs can be automatically generated from the service defined specification.

If you need one of those in your development process, you should consider using Open API.

## Alternatives

There is [RAML](https://raml.org/), which is, as Swagger, another DSL for REST APIs. I am not sure about the project state.

If you are not locked to use REST, and can use gRPC for example, [protobuf](https://developers.google.com/protocol-buffers/)
is a DSL that plays a similar role to Open API but in RPC.

## Before You Start

**It takes time** to gain control over the swagger specification, but after a short effort they become very easy to
use and understand.

**The specification is huge**, there are a lot of tricks, corner cases, and results that can be achieved in
many different ways. The way I find the best to handle it is:

1. Understand the tools and their limitations. Try to use them, and see how they correspond
   to different specifications in Open API (Not all of them are compliant with all the small details of the
   specification, and all the versions of the specification).
2. Think about trade-offs between the readability of the swagger and the usage of the generated code.
3. Get to "conventions" within the specification, get to agreement about them with your team-mates, and adopt them in
   your organization.

## Example

Check out the [pet-store example](https://editor.swagger.io/) from [swagger.io](https://swagger.io) website.
The surprising thing is that it is not "perfect", and have some non-"RESTful" endpoints in it.

> * Paths should be in plural form. In the example it is in singular: `/pet` should have been `/pets`, 
    `/pet/{petId}` should have been `/pets/{petId}`.
> * There are endpoints that should have been query params of other endpoints. The endpoint with path 
    `/pet/findByStatus` should have been a query param `status` for the `/pets` endpoint: `/pets?status=<status>`.
> * To update pet details, there is an endpoint `PUT /pet`, with the ID is passed in the body. The standard way to
    update an entity is to have an endpoint `PUT /pets/{petId}`. The standard is also to return the updated pet, in the
    example, nothing is returned.
> * Create operation should return the created object, in the example nothing is returned.

However, it does give a good feeling about how to write a swagger file.

Below, there is a very short example of a pet store, including three endpoints: pet-list, pet-create and pet-get
operations, with a definition of a pet object. It is pretty descriptive, so I won't explain how to write a swagger
file. The example is here just to get a feeling what you are going into.

Take a few minutes, go through the example and try to understand it.

```yaml
swagger: '2.0'
info:
  version: '1.0.0'
  title: Minimal Pet Store Example
schemes: [http]
host: example.org
basePath: /api
consumes: [application/json]
produces: [application/json]
paths:
  /pets:
    post:
      tags: [pet]
      operationId: Create
      parameters:
      - in: body
        name: pet
        required: true
        schema:
          $ref: '#/definitions/Pet'
      responses:
        201:
          description: Pet Created
          schema:
            $ref: '#/definitions/Pet'
        400:
          description: Bad Request
    get:
      tags: [pet]
      operationId: List
      parameters:
      - in: query
        name: kind
        type: string
      responses:
        200:
          description: 'Pet list'
          schema:
            type: array
            items:
                $ref: '#/definitions/Pet'
  /pets/{petId}:
    get:
      tags: [pet]
      operationId: Get
      parameters:
      - name: petId
        in: path
        required: true
        type: integer
        format: int64
      responses:
        200:
          description: Pet get
          schema:
            $ref: '#/definitions/Pet'
        400:
          description: Bad Request
        404:
          description: Pet Not Found

definitions:
  Pet:
    type: object
    required:
    - name
    properties:
      id:
        type: integer
        format: int64
        readOnly: true
      kind:
        type: string
        example: dog
      name:
        type: string
        example: Bobby
```

## Tools

Here is a list of a few tools we use in Stratoscale, you may find some of them useful.

### Editing Swagger Files:

* [Swagger Editor](https://editor.swagger.io/) - Online editor of swagger files.
* [Jetbrain's Swagger Editor](https://plugins.jetbrains.com/plugin/8347-swagger-plugin) - A really good tool for editing
  swagger files - provides auto completion and generates browser UI of the swagger file.
  
### Generating Code - client or server

* [Swagger Codegen](https://swagger.io/tools/swagger-codegen) - A tool for code generation (clients and servers)
  in many different languages.
* [go-swagger](https://github.com/go-swagger/go-swagger) - Generates go code, and will be the subject of a following post.

### Mock Servers

* [prism](https://github.com/stoplightio/prism) - Create random responses, and validate scheme. Does not provide
  a stateful behavior - a created pet won't appear in the pet list.

* [imposter-openapi](https://github.com/outofcoffee/imposter) - Creates a mock server that serves requests.
  It needs to have response examples for returning valid responses, otherwise it only returns 404 for routes it
  does not know, and 200 if the route is valid. For an invalid request I also got 200, instead of a 400 that
  I would expect.
   
### Automatic CLI

[open-cli](https://github.com/sharbov/open-cli) is an automatic CLI for Open API servers. Most servers generated from a
swagger file expose a `GET /swagger.json` endpoint, which returns the same swagger that describes the server. 
This tool takes advantage of this endpoint and provides a CLI for the server.
If the server does not expose such endpoint but you have the swagger file locally, this tool can also work with it.
[Shay](https://github.com/sharbov), the creator of this tool, also works at Stratoscale.

## Stay Tuned

In the [following post](/go-swagger) I'll talk about [go-swagger](https://github.com/go-swagger/go-swagger) - a Go code generation
tool from swagger files.
