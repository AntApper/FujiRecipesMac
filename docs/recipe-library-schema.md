# Recipe Library Schema

The scraper writes a JSON payload with metadata and a `recipes` array.

```json
{
  "source": "Fuji X Weekly",
  "sourceUrl": "https://fujixweekly.com/fujifilm-x-trans-v-recipes/",
  "sensorGeneration": "X-Trans V",
  "scrapedAt": "2026-06-22T00:00:00Z",
  "recipeCount": 1,
  "recipes": [
    {
      "id": "pro-negative-160c",
      "name": "PRO Negative 160C",
      "title": "PRO Negative 160C - Fujifilm X100VI Film Simulation Recipe",
      "source": "Fuji X Weekly",
      "sourceUrl": "https://fujixweekly.com/.../",
      "sensorGeneration": "X-Trans V",
      "date": "2024-03-27T00:00:00+00:00",
      "previewImageUrl": "https://...",
      "imageUrls": [],
      "compatibleCameras": ["X100VI"],
      "tags": [],
      "settings": {
        "filmSimulation": "Reala Ace",
        "dynamicRange": "DR200",
        "grainEffect": "Weak, Small",
        "colorChromeEffect": "Strong",
        "colorChromeFxBlue": "Off",
        "whiteBalance": "Auto, +1 Red & -2 Blue",
        "highlight": "-1",
        "shadow": "-1",
        "color": "+4",
        "sharpness": "-1",
        "highIsoNr": "-4",
        "clarity": "-2",
        "iso": "Auto, up to ISO 6400",
        "exposureCompensation": "0 to +2/3"
      },
      "settingCount": 14,
      "parseStatus": "ok",
      "reviewNotes": []
    }
  ]
}
```

## Parse Status

- `ok` means at least eight recognized settings were parsed.
- `needs_review` means the page may contain multiple recipes, unusual formatting, or a settings block that did not match the parser.

## App Mapping Notes

Settings are stored as strings first. Numeric conversion and Fuji PTP property mapping should happen in a separate import/mapping layer so that unusual values such as `Auto, +1 Red & -2 Blue` and `0 to +2/3` are preserved.

## Curated Public Imports

Creator-published recipes that are not part of the Fuji X Weekly scrape live in
`data/curated/`. Each imported recipe must retain:

- `sourceUrl`, `sourceType`, and `creator`;
- a `provenance` object with retrieval date, import method, and reuse status;
- only factual setting values needed to configure the camera—never copied prose
  or images; and
- `mappingCompleteness`, distinguishing preset-slot mappings from active-setting
  mappings that still require a hardware probe.

Run `python3 tools/validate_recipe_imports.py` before combining an import with
the scraped catalog. The validator rejects duplicate IDs, normalized names, and
normalized setting fingerprints across source datasets.
