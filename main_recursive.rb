require "./lib/pb_result_parser_doubles"
require "./lib/pb_result_parser_singles"

puts ARGV

folder = ARGV[0]
html_files = Dir["#{folder}/**/*.htm{l,*}"]

puts "All files: #{html_files}"

first_singles_iteration = true
first_doubles_iteration = true

html_files.each do |pb_results_html|
  event_name = PbResultsParser::Doubles.new(File.open(pb_results_html)).event_name
  is_singles_file = event_name.downcase.include?('singles')

  _parser_class = is_singles_file ? PbResultsParser::Singles : PbResultsParser::Doubles

  filename = is_singles_file ? "results_singles" : "results_doubles"
  concat_mode = is_singles_file ? !first_singles_iteration : !first_doubles_iteration

  _parser_class.to_csv(File.open(pb_results_html), filename, concat_mode)
  if is_singles_file
    first_singles_iteration = false
  else
    first_doubles_iteration = false
  end
rescue StandardError => e
  puts "Error scraping #{pb_results_html}: #{e.message} -> #{e.backtrace.join("\n")}"
  binding.pry
end
