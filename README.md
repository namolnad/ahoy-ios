# Ahoy iOS

Simple visit-attribution and analytics library for Apple Platforms for integration with your Rails [Ahoy](http://github.com/ankane/ahoy) backend.

🌖 User visit tracking

📥 Visit attribution through UTM & referrer parameters

📆 Simple, straightforward, in-house event tracking

[![Actions Status](https://github.com/namolnad/ahoy-ios/workflows/tests/badge.svg)](https://github.com/namolnad/ahoy-ios/actions)

## Installation

The Ahoy library can be easily installed using Swift Package Manager. See the [Apple docs](https://developer.apple.com/documentation/xcode/adding_package_dependencies_to_your_app) for instructions on adding a package to your project.

Requires Swift 6 (Xcode 16 or later). The package builds in the Swift 6 language mode. `Ahoy` is an actor, so one instance can be shared freely across actors and tasks.

## Usage

To get started you need to initialize an instance of an Ahoy client. The initializer takes a configuration object, which requires you to provide a `baseUrl` as well as an `ApplicationEnvironment` object.

`UIDevice` is main-actor isolated, so build the client there — from your `App` initializer, for example. `Ahoy` is an actor, so the instance can be shared anywhere once it exists.

``` swift
import Ahoy
import UIKit

@MainActor
func makeAhoyClient() -> Ahoy {
    .init(
        configuration: .init(
            environment: .init(
                platform: UIDevice.current.systemName,
                appVersion: "1.0.2",
                osVersion: UIDevice.current.systemVersion
            ),
            baseUrl: URL(string: "https://your-server.com")!
        )
    )
}
```
### Configuration
The configuation object has intelligent defaults _(listed below in parens)_, but allows you to a to provide overrides for a series of values:
- visitDuration _(4 hours)_
- automaticVisitRenewal _(true)_
- visitParams _(none)_
- urlRequestHandler _(`URLSession.shared.data(for:)`)_
- Routing
    - ahoyPath _("ahoy")_
    - visitsPath _("visits")_
    - eventsPath _("events")_

Beyond configuration, you can also provide your own `AhoyTokenManager` and `RequestInterceptor`s at initialization _(replaceable later via `setRequestInterceptors(_:)`)_ for custom token management and pre-flight Ahoy request modifications, respectively.

### Visits
A visit is valid for `visitDuration`, measured from the moment it is created — the same fixed window used by [ahoy.js](https://github.com/ankane/ahoy.js) and the `Ahoy.visit_duration` setting in the Ahoy gem. You do not need to track time between events yourself.

By default Ahoy keeps the visit current for you. It registers a new visit whenever the previous one has lapsed, at the two moments the web library would:

- when your application becomes active _(the analogue of a web page load)_
- lazily, when you track an event

So for most applications, tracking events is all you need to do — a visit will be created on demand:

``` swift
ahoy.track("ride_details.update_driver_rating", properties: ["driver_id": 4])
```

If your visits carry attribution data such as utm parameters or a referrer, supply it via `visitParams` so the visits Ahoy creates on your behalf include it:

``` swift
let ahoy: Ahoy = .init(
    configuration: .init(
        environment: environment,
        baseUrl: URL(string: "https://your-server.com")!,
        visitParams: { ["utm_source": currentAttribution.utmSource] }
    )
)
```

### Tracking a visit manually
To track a visit yourself — at application launch, or to attach params to one specific visit — call `trackVisit`. Calling it while a visit is still current re-registers the same visit token, which your Ahoy server ignores.

``` swift
let visit = try await ahoy.trackVisit(additionalParams: ["utm_source": "some-place"])
```

Callers that arrive while a visit request is already in flight await that same request rather than starting another, so concurrent tracking cannot scatter a batch of events across several visits.

To take over visit management entirely, set `automaticVisitRenewal` to `false`. Ahoy will then never create a visit on its own, and `track(events:)` throws `AhoyError.noVisit` until you have registered one. `ensureCurrentVisit()` is available if you want the renew-if-expired behavior at a moment of your choosing.

### Tracking events
Events are sent against the current visit, renewing it first when necessary.
``` swift
/// For bulk-tracking, use the `track(events:)` function
let pendingEvents: [Event] = [
    Event(name: "ride_details.update_driver_rating", properties: ["driver_id": 4]),
    Event(name: "ride_details.increase_tip", properties: ["driver_id": 4])
]

try await ahoy.track(events: pendingEvents)

/// If you prefer to fire events individually, use the fire-and-forget convenience method. It is
/// callable from anywhere — synchronous or asynchronous — and never throws.
ahoy.track("ride_details.update_driver_rating", properties: ["driver_id": 4])

/// If your event does not require properties, they can be omitted
ahoy.track("ride_details.update_driver_rating")
```

### Attaching a user
`attach(userId:)` adds a `user_id` root key to subsequent event payloads. The attachment persists across visit renewals until you call `detachUser()`. _(Note: this does not authenticate the user on your server.)_

``` swift
await ahoy.attach(userId: "12345")
```

### Other goodies
To access the current visit directly, use your Ahoy client's `currentVisit` property. Additionally, you can use the `headers` property to add `Ahoy-Visitor` and `Ahoy-Visit` tokens to your own requests as needed.

``` swift
var request = URLRequest(url: url)

for (field, value) in await ahoy.headers {
    request.setValue(value, forHTTPHeaderField: field)
}
```

To observe visits as they are registered, iterate `visits`. Each call returns an independent sequence beginning with the current visit, so several observers can iterate at once.

``` swift
for await visit in ahoy.visits {
    print(visit)
}
```
