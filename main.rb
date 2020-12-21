require "./lib/pb_result_parser"

puts ARGV
ARGV.each do |pb_results_html|
  puts "All matches"
  pp PbResultsParser.results(File.open(pb_results_html))
  puts "==="
  PbResultsParser.to_csv(File.open(pb_results_html), "results")
end
