# Data Source: Fuji X Weekly

Source page: https://fujixweekly.com/fujifilm-x-trans-v-recipes/

The scraper reads the X-Trans V recipe index and follows recipe links from Fuji X Weekly. The resulting local data is intended for private camera recipe management.

## Use Constraint

The recipe text/settings are third-party content. Keep this local/private unless permission or a licensing arrangement is obtained.

## Scrape Strategy

- Extract recipe links from the X-Trans V index page.
- Fetch each recipe page with a small delay.
- Preserve every source URL.
- Parse recognized camera setting labels into normalized field names.
- Mark low-confidence pages as `needs_review`.

## Known Parser Limitations

- Some Fuji X Weekly pages contain multiple recipes in one article.
- Some pages include comments with recipe-like settings; the parser only reads the article `entry-content` when possible, but manual review is still useful.
- Some newer recipes may use fields not yet listed in the scraper aliases.
