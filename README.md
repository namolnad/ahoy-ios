# Ahoy iOS

Simple visit-attribution and analytics library for Apple Platforms for integration with your Rails [Ahoy](http://github.com/ankane/ahoy) backend.

🌖 User visit tracking

📥 Visit attribution through UTM & referrer parameters

📆 Simple, straightforward, in-house event tracking

[![Actions Status](https://github.com/namolnad/ahoy-ios/workflows/tests/badge.svg)](https://github.com/namolnad/ahoy-ios/actions)

## Installation

The Ahoy library can be easily installed using Swift Package Manager. See the [Apple docs](https://developer.apple.com/documentation/xcode/adding_package_dependencies_to_your_app) for instructions on adding a package to your project.

Requires Swift 6 (Xcode 16 or later). The package builds in the Swift 6 language mode, and the `Ahoy` client is `Sendable` — you can share one instance across actors and tasks, and track from any isolation domain.

## Usage

To get started you need to initialize an instance of an Ahoy client. The initializer takes a configuration object, which requires you to provide a `baseUrl` as well as an `ApplicationEnvironment` object.
``` swift
import Ahoy

let ahoy: Ahoy = .init(
    configuration: .init(
    environment: .init(
        platform: UIDevice.current.systemName,
        appVersion: "1.0.2",
        osVersion: UIDevice.current.systemVersion
    ),
    baseUrl: URL(string: "https://your-server.com")!
  )
)
```
### Configuration
The configuation object has intelligent defaults _(listed below in parens)_, but allows you to a to provide overrides for a series of values:
- visitDuration _(4 hours)_
- automaticVisitRenewal _(true)_
- visitParams _(none)_
- urlRequestHandler _(`URLSession.shared.dataTaskPublisher`)_
- Routing
    - ahoyPath _("ahoy")_
    - visitsPath _("visits")_
    - eventsPath _("events")_

Beyond configuration, you can also provide your own `AhoyTokenManager` and `RequestInterceptor`s at initialization _(`requestInterceptors` can be modified later)_ for custom token management and pre-flight Ahoy request modifications, respectively.

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
        environment: .init(/* ... */),
        baseUrl: URL(string: "https://your-server.com")!,
        visitParams: { ["utm_source": deepLink.utmSource] }
    )
)
```

### Tracking a visit manually
To track a visit yourself — at application launch, or to attach params to one specific visit — call `trackVisit`. Calling it while a visit is still current re-registers the same visit token, which your Ahoy server ignores.

``` swift
ahoy.trackVisit(additionalParams: ["utm_source": "some-place"])
    .sink(receiveCompletion: { _ in }, receiveOutput: { visit in print(visit) })
    .store(in: &cancellables)
```

To take over visit management entirely, set `automaticVisitRenewal` to `false`. Ahoy will then never create a visit on its own, and `track(events:)` fails with `AhoyError.noVisit` until you have registered one. `ensureCurrentVisit()` is available if you want the renew-if-expired behavior at a moment of your choosing.

### Tracking events
Events are sent against the current visit, renewing it first when necessary.
``` swift
/// For bulk-tracking, use the `track(events:)` function
var pendingEvents: [Event] = []
pendingEvents.append(Event(name: "ride_details.update_driver_rating", properties: ["driver_id": 4]))
pendingEvents.append(Event(name: "ride_details.increase_tip", properties: ["driver_id": 4]))

ahoy.track(events: pendingEvents)
    .sink(
        receiveCompletion: { _ in }, // handle error as needed
        receiveValue: { pendingEvents.removeAll() }
    )
    .store(in: &cancellables)

/// If you prefer to fire events individually, you can use the fire-and-forget convenience method
ahoy.track("ride_details.update_driver_rating", properties: ["driver_id": 4])

/// If your event does not require properties, they can be omitted
ahoy.track("ride_details.update_driver_rating")
```

### Attaching a user
`attach(userId:)` adds a `user_id` root key to subsequent event payloads. The attachment persists across visit renewals until you call `detachUser()`. _(Note: this does not authenticate the user on your server.)_

``` swift
ahoy.attach(userId: "12345")
```

### Other goodies
To access the current visit directly, simply use your Ahoy client's `currentVisit` property. _(There is also a currentVisitPublisher you can listen to.)_ Additionally, you can use the `headers` property to add `Ahoy-Visitor` and `Ahoy-Visit` tokens to your own requests as needed.
