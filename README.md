# Mushroom Signal

A native macOS app and desktop widget that rates the chance of finding mushrooms in each Slovak region, based on recent weather.

- **Map:** the forecast for all 8 Slovak regions (kraje).
- **Species list:** 27 Slovak species (20 edible, 4 to treat with caution, 3 poisonous), with what each one needs and a photo of each edible one.
- **Widget:** a shortlist of the best species for your region, in small, medium and large sizes.

The app interface is in Slovak.

## How it works

The app fetches recent and forecast weather for each region from [Open-Meteo](https://open-meteo.com) (free, no API key). It scores the weather against what each species needs (rain, temperature, season) and shows the result on the map, in the list and in the widget.

**Safety:** this is a forecast of *where to look*, not an identification tool. Never eat a mushroom you have not identified with certainty. Poisonous species and look-alikes are marked in the app.

## Requirements

- macOS 14 or later
- Xcode with Swift 5.10 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (only if you change `project.yml`)

## Build and test

The core logic (scoring, weather client, data) is a Swift package. It builds and tests without Xcode:

```sh
swift test --package-path MushroomSignalCore
```

The app and widget are in `MushroomSignal.xcodeproj`, which is generated from `project.yml`:

1. Open `project.yml` and set `DEVELOPMENT_TEAM` to **your own** Apple team ID (both targets). The widget cannot read the app's data without a real signing team.
2. Run `xcodegen generate`.
3. Build and run:

   ```sh
   xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build
   cp -R DerivedData/Build/Products/Debug/MushroomSignal.app /Applications/
   open /Applications/MushroomSignal.app
   ```

The app must run from `/Applications`. If it runs from any other folder, macOS does not show the widget in the widget gallery.

## Project layout

```
MushroomSignal/          the macOS app (SwiftUI)
MushroomSignalWidget/    the desktop widget (WidgetKit)
MushroomSignalCore/      the Swift package: scoring, weather, species data, tests
MushroomSignalTests/     app tests
project.yml              XcodeGen project definition
docs/                    design specs, plans and known issues
```

## Contributing

Pull requests are welcome. Some ideas:

- more species, or better season and weather data for the existing ones
- better scoring based on real foraging finds
- support for other countries or regions
- an English interface

Before you open a pull request, run `swift test --package-path MushroomSignalCore`. For a larger change, open an issue first so we can agree on the approach.

## Photo credits

The species photos come from Wikimedia Commons. They are loaded from Wikimedia at runtime and are not stored in this repo. Each photo keeps its own license and author. These are listed in `MushroomSignalCore/Sources/MushroomSignalCore/Data/species-photos.json` and on the app's photo credits screen. The MIT license below covers the code only, not the photos.

## License

[MIT](LICENSE) © 2026 Alexander Salinka
