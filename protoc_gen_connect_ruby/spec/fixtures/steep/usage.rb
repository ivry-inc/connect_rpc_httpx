# frozen_string_literal: true

# Calls into the generated clients. signatures_spec type checks this file against the generated
# signatures, and expects an error on exactly the lines marked "error".

client = Acme::Greet::V1::GreetServiceClient.new("http://greet.test")

client.greet(Acme::Greet::V1::GreetRequest.new, timeout: 1).greeting
client.greet({name: "Ruby", nested: {value: "a", child: {value: "b"}}}, timeout: 1)
client.greet(name: "Ruby", tags: ["a"], extras: {key: {value: "a"}}, mood: :MOOD_HAPPY, at: Time.now, weight: 1)
client.greet(name: "Ruby", headers: {"x-request-id" => "a"}, timeout: 1.5)
client.greet
client.greet_stream(name: "Ruby") { |response| response.greeting }
client.greet_many([{name: "a"}, Acme::Greet::V1::GreetRequest.new])
client.greet_many(["a", "b"].map { |name| {name:} })
request = Acme::Greet::V1::GreetRequest.new(name: "Ruby")
client.greet(request)
client.converse([Acme::Greet::V1::GreetRequest.new].each)
Acme::Shapes::Shape_serviceClient.new("http://shapes.test").describe({timeout: 3}, timeout: 1)
Acme::Shapes::Shape_serviceClient.new("http://shapes.test").describe(origin: {child: {value: "a"}}, flags: {1 => true})

client.greet(name: 1) # error
client.greet(nested: {valu: "a"}) # error
client.greet(mood: :MOOD_SAD) # error
client.greet(extras: {key: {child: {value: 1}}}) # error
client.greet_many([{nme: "a"}]) # error
client.greet(Acme::Greet::V1::GreetResponse.new) # error
fields = {name: "Ruby"}
client.greet(fields) # error
client.converse([{name: "a"}].each) # error
