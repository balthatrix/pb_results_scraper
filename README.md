### Prerequisites
- Ruby 2.3+ is installed

### Getting Started
$`git clone https://github.com/balthatrix/pb_results_scraper`
$`cd pb_results_scraper`
$`bundle install`

### Parsing a Tourney Webpage
1. Download a tournament results page from pickleballtournaments. For example, the html file in test/fixtures of this repository is from this page: https://www.pickleballtournaments.com/Tournaments/VA/2020_WCCPICKLEBALL_4528/MD19+_17.htm

2. Run `ruby main.rb <path to the downloaded html file>`

3. Check for `results.csv` in your current working directory for results.
