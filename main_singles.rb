require "./lib/pb_result_parser_singles"

puts ARGV
first_iteration = true
ARGV.each do |pb_results_html|
  next if pb_results_html == "true"

  puts "All matches"
  begin
    pp PbResultsParser::Singles.results(File.open(pb_results_html))
  rescue StandardError => e
    puts "SINGLES Error scraping #{pb_results_html}: #{e.message} -> #{e.backtrace.join("\n")}"
    return
  end
  puts "==="

  PbResultsParser::Singles.to_csv(File.open(pb_results_html), "results", ARGV.last == "true" || !first_iteration)
  first_iteration = false
end
