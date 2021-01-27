require "./lib/pb_result_parser"

puts ARGV
first_iteration = true
ARGV.each do |pb_results_html|
  next if pb_results_html == "true"
  puts "All matches"
  pp PbResultsParser.results(File.open(pb_results_html))
  puts "==="
  PbResultsParser.to_csv(File.open(pb_results_html), "results", ARGV.last == "true" || !first_iteration)
  first_iteration = false
end
