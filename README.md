# Ahoy iOS

Simple visit-attribution and analytics library for Apple Platforms for integration with your Rails [Ahoy](http://github.com/ankane/ahoy) backend.

🌖 User visit tracking

📥 Visit attribution through UTM & referrer parameters

📆 Simple, straightforward, in-house event tracking

[![Actions Status](https://github.com/namolnad/ahoy-ios/workflows/tests/badge.svg)](https://github.com/namolnad/ahoy-ios/actions)

## Installation

The Ahoy library can be easily installed using Swift Package Manager. See the [Apple docs](https://developer.apple.com/documentation/xcode/adding_package_dependencies_to_your_app) for instructions on adding a package to your project.

## Usage

To get started you need to initialize an instance of an Ahoy client. The initializer takes a configuration object, which requires you to provide a `baseUrl` (your server location) as well as an `ApplicationEnvironment` object.
``` swift
import Ahoy

let ahoy: Ahoy = .init(
    configuration: .init(
    environment: .init(),
    baseUrl: URL(string: "https://your-sever.com")!
)
```
### Configuration
The configuation object has intelligent defaults (listed below in parens), but allows you to a to provide overrides for a series of values:
- visitDuration (30 minutes)
- urlRequestHandler (URLSession.shared.dataTaskPublisher)
- Routing
    - ahoyPath ("ahoy")
    - visitsPath ("visits")
    - eventsPath ("events")

Beyond configuration, you can also provide your own `AhoyTokenManager` and `RequestInterceptor`s (can be modified later) for custom token management and pre-flight Ahoy request modifications, respectively.

### Tracking a visit
After your client is initialized (ensure you maintain a reference), you'll need to track a visit, typically done at application launch. If desired, you can pass custom data such as utm parameters, referrer, etc.

``` swift
ahoy.trackVisit()
    .sink(recieveCompletion: { _ in }, receiveOutput: { visit in  print(visit) })
    .store(in: &cancellables)
```

### Tracking events
After your client has successfully registered a visit, you can send begin to send events to your server.
``` swift
ahoy.track(events: [myFirstEvent, mySecondEvent])
    .sink(recieveCompletion: { _ in }, receiveOutput: { _ in })
    .store(in: &cancellables)
```

### Other goodies
To access the current visit directly, simply use your Ahoy client's `currentVisit` property. (there is also a publisher you can listen to). Additionally, you can use your the `headers` property to add `Ahoy-Visitor` and `Ahoy-Visit` tokens to your own requests as needed.
