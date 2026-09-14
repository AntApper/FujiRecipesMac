# Privacy and Third-Party Notices (Release Scaffold)

This is a release-preparation scaffold, not a completed public privacy policy
or third-party attribution package. It must be reviewed by the publisher
before distribution.

## Observed application data handling

- Recipe selections, favorites, and loadout metadata are stored locally through
  the app's local persistence mechanisms.
- When a user chooses a RAF file for conversion, its bytes are sent directly
  to the connected camera by the local helper. The repository contains no
  implemented cloud upload, analytics, advertising, account, or telemetry
  service.
- Camera settings and USB/PTP responses are processed locally to display
  camera state and command results.
- Debug logging may include technical camera-operation details. A release
  policy must state whether logs are retained, exported, or included in support
  requests.

These statements describe code and configuration observed in this repository;
they do not substitute for a legal review or a runtime network audit of a
shipping app.

## Third-party software

- **libusb-1.0** is required by `x100vi_helper`. The packaged helper runtime is
  accompanied by `ThirdPartyNotices/libusb-COPYING.txt`; its SHA-256 and source
  provenance are recorded in `x100vi_helper.provenance.json`. This technical
  inclusion does not replace a publisher review of the exact libusb version,
  its license obligations, or the final signed artifact.
- **libgphoto2** is used by optional development/backend paths. Any distributed
  copy requires its applicable license notices and source/offer obligations to
  be reviewed before release.

Before publishing, create a shipped `ThirdPartyNotices` document from the exact
versions and licenses of all bundled dependencies. Do not claim that a notice
file covers a dependency unless that binary is actually included in the
release.

## Content and image licensing

Recipe source, recipe text, camera sample images, and visual assets require
publisher confirmation of redistribution rights. That confirmation is pending.
Do not ship this scaffold as evidence that recipe or image licenses have been
cleared.

## Release checklist additions

1. Obtain legal/publisher approval for a public privacy policy and support-log
   handling.
2. Inventory each distributed dependency from the final signed artifact.
3. Include matching license and attribution text for each dependency.
4. Confirm recipe, image, and visual-asset redistribution rights.
