# Notices

MG EV for iOS is licensed under the Apache License, Version 2.0 (see [LICENSE](LICENSE)).
It includes or is derived from the following work, under their own licences.

## Volta

The MG i-SMART client (`Packages/MGEVKit/Sources/MGKit`), the car models and battery profile
(`Packages/MGEVKit/Sources/EVCore`) and their tests are Swift ports of Volta,
https://github.com/irshadm/volta-android, Copyright 2026 Irshad, licensed under the Apache License, Version 2.0.
Changes: rewritten in Swift for iOS; structure and behaviour follow the original.

## mg-ismart-india-client

Volta's MG client is itself a port of https://github.com/john-lazarus/mg-ismart-india-client. The test vectors in
`Packages/MGEVKit/Tests/MGKitTests/Resources/ismart_vectors.json` were produced by that client.

MIT License

Copyright (c) 2026 John Lazarus

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## saic-python-mqtt-gateway

Tyre pressures on cars other than the Windsor are read in 0.04 bar steps, following
https://github.com/SAIC-iSmart-API/saic-python-mqtt-gateway (MIT licence), as Volta does. No code is copied from it.

## Trademarks

This is an independent project, not made by, endorsed by or affiliated with MG Motor India or SAIC. "MG" and
"i-SMART" are their trademarks, used only to say what the app works with.
