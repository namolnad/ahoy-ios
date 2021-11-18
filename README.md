# Ahoy iOS

Simple visit-attribution and analytics library for Apple Platforms for integration with your Rails [Ahoy](http://github.com/ankane/ahoy) backend.

🌖 User visit tracking

📥 Visit attribution through UTM & referrer parameters

📆 Simple, straightforward, in-house event tracking

[![Actions Status](https://github.com/namolnad/ahoy-ios/workflows/tests/badge.svg)](https://github.com/namolnad/ahoy-ios/actions)

## Installation

The Ahoy library can be easily installed using Swift Package Manager. See the [Apple docs](https://developer.apple.com/documentation/xcode/adding_package_dependencies_to_your_app) for instructions on adding a package to your project.

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
- visitDuration _(30 minutes)_
- urlRequestHandler _(`URLSession.shared.dataTaskPublisher`)_
- Routing
    - ahoyPath _("ahoy")_
    - visitsPath _("visits")_
    - eventsPath _("events")_

Beyond configuration, you can also provide your own `AhoyTokenManager` and `RequestInterceptor`s at initialization _(`requestInterceptors` can be modified later)_ for custom token management and pre-flight Ahoy request modifications, respectively.

### Tracking a visit
After your client is initialized — ensure you maintain a reference — you'll need to track a visit, typically done at application launch. If desired, you can pass custom data such as utm parameters, referrer, etc.

``` swift
ahoy.trackVisit()
    .sink(receiveCompletion: { _ in }, receiveOutput: { visit in print(visit) })
    .store(in: &cancellables)
```

### Tracking events
After your client has successfully registered a visit, you can begin to send events to your server.
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

### Other goodies
To access the current visit directly, simply use your Ahoy client's `currentVisit` property. _(There is also a currentVisitPublisher you can listen to.)_ Additionally, you can use the `headers` property to add `Ahoy-Visitor` and `Ahoy-Visit` tokens to your own requests as needed.
