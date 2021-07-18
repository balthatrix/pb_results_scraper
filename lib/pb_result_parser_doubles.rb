require 'nokogiri'
require 'pry'
require 'csv'
require_relative './pb_result_parser_base'

# E.G. initialization:
=begin
require './lib/pb_result_parser.rb'
parser = PbResultsParser.new(File.open("./test/fixture/winchester_country_club_tourney.html"))
scores = parser.all_td_with_score
team_as = scores.map{|s| {
  score: s.children.first.to_s,
  team_a: parser.find_team_a(s).children.first.to_s,
  team_b: parser.find_team_b(s).children.first.to_s,
  winner: parser.winner(s).children.first.to_s
} }

require './lib/pb_result_parser.rb'
results = PbResultsParser.results(File.open("./test/fixture/winchester_country_club_tourney.html"))
PbResultsParser.to_csv(File.open("./test/fixture/winchester_country_club_tourney.html"), "results")
=end
class PbResultsParser
  class Doubles < Base
    attr_accessor :teams

    def self.results(io)
      parser = new(io)

      parser.register_teams

      scores = parser.all_td_with_score

      matches = []
      scores.each do |s|
        score_text = s.children.first.to_s.gsub(/,,/, ",")

        # skip score being 0 - 0 for forfeit, etc...
        next if score_text.include?('0-0') || score_text.downcase.include?('withdrawal') || score_text.downcase.include?('forfeit')

        team_a_text = parser.find_team_a(s).children.first.to_s
        team_a_hash = parser.teams[team_a_text.to_sym]
        binding.pry if team_a_hash.nil?

        team_b_text = parser.find_team_b(s).children.first.to_s
        team_b_hash = parser.teams[team_b_text.to_sym]
        binding.pry if team_b_hash.nil?

        winner_text = parser.winner(s).children.first.to_s
        winner_hash = parser.teams[winner_text.to_sym]
        binding.pry if winner_hash.nil?

        winner_score_index = parser.winner_point_position_in_match(score_text)
        loser_score_index = parser.loser_point_position_in_match(score_text)

        team_a_is_winner = winner_hash == team_a_hash
        team_a_score_index = team_a_is_winner ? winner_score_index : loser_score_index
        team_b_score_index = team_a_is_winner ? loser_score_index : winner_score_index

        games = parser.parsed_scores_from_raw(score_text)
        team_a_scores = games.map{|g| g[team_a_score_index] }
        team_b_scores = games.map{|g| g[team_b_score_index] }

        matches.push({
          raw_scores: score_text.gsub(/&nbsp;/, " "),
          team_a: team_a_hash,
          team_b: team_b_hash,
          team_a_scores: team_a_scores,
          team_b_scores: team_b_scores,
          winner: winner_hash,
          tournament_name: parser.tournament_name,
          event_name: parser.event_name,
          event_date: parser.event_date
        })
      rescue StandardError => e
        binding.pry
        raise e
      end

      matches
    end

    def clean_str str
      new_str = ""
      str.chars.each do |c|
        if c.bytes.size > 1
          # binding.pry
          new_str << " "
        else
          new_str << c
        end
      end
      new_str
    end

    def self.to_csv(io, result_filename, cat_mode=false)
      matches = results(io)
      CSV.open("#{result_filename}.csv", cat_mode ? "ab" : "wb") do |csv|
        csv << [
          "Tournament Name",
          "Event Name",
          "Event Date",
          "Team A Player 1",
          "Team A Player 2",
          "Team B Player 1",
          "Team B Player 2",
          "Winning Team",
          "Team A Points Game 1",
          "Team B Points Game 1",
          "Team A Points Game 2",
          "Team B Points Game 2",
          "Team A Points Game 3",
          "Team B Points Game 3",
          "Team A Points Game 4",
          "Team B Points Game 4"
        ] unless cat_mode

        matches.each do |match|
          row = []

          puts "Adding match to csv:"
          puts match
          puts "===="

          # heading info
          if match[:tournament_name] == match[:event_name]
            row.push(io.path)
          else
            row.push(match[:tournament_name])
          end
          row.push(match[:event_name])
          row.push(match[:event_date])

          # team a
          row.push("#{match[:team_a][:player_a_first]} #{match[:team_a][:player_a_last]}")
          row.push("#{match[:team_a][:player_b_first]} #{match[:team_a][:player_b_last]}")

          # team b
          row.push("#{match[:team_b][:player_a_first]} #{match[:team_b][:player_a_last]}")
          row.push("#{match[:team_b][:player_b_first]} #{match[:team_b][:player_b_last]}")

          # winning team
          row.push("#{match[:winner][:player_a_first]} #{match[:winner][:player_a_last]} and #{match[:winner][:player_b_first]} #{match[:winner][:player_b_last]}")

          match[:team_a_scores].each_with_index do |score, i|
            row.push(score)
            row.push(match[:team_b_scores][i])
          end

          csv << row
        end
      end
    end

    def initialize(io)
      @io = io
      @document = Nokogiri::HTML(io)
    end



    def find_team_a(score_td)
      # the score td element might be contained within another table...
      # this handles that exception
      if td_siblings(score_td).size == 1
        score_td = score_td.parent
        while score_td.name != 'td'
          score_td = score_td.parent
        end
      end

      prev_index = index_of_td(score_td) - 1
      prev_td = td_siblings(score_td)[prev_index]

      # for team a, allway ascend at least 1 row
      tr_elem = previous_tr_elem(prev_td.parent)
      # binding.pry if tr_elem.nil?
      # scan tds upward to find the path of bracket based on bottom border style
      while above_td = td_children(tr_elem)[prev_index]
        if above_td.nil?
          raise "Could not find team a in upward pathfinding in bracket for score: #{score_td}"
        end

        # found the bracket path node
        if above_td.attributes['style'] && above_td.attributes['style'].value.match(/border\-bottom/)
          break
        end

        tr_elem = previous_tr_elem(tr_elem)
      end

      leftward_td = above_td
      while(!name_pattern_matches?(leftward_td.children.first.to_s))
        leftward_td = previous_td_elem(leftward_td)
        if leftward_td.nil?
          raise "Could not find team a in leftward pathfinding in bracket for score: #{score_td}"
        end
      end

      leftward_td
    end

    def find_team_b(score_td)
      # the score td element might be contained within another table...
      # this handles that exception
      if td_siblings(score_td).size == 1
        score_td = score_td.parent
        while score_td.name != 'td'
          score_td = score_td.parent
        end
      end

      prev_index = index_of_td(score_td) - 1
      prev_td = td_siblings(score_td)[prev_index]

      if name_pattern_matches?(prev_td.children.first.to_s)
        return prev_td
      else
        # binding.pry if score_td.children.first.text == '10-12,11-9,11-3'
        #scan downward until you find a bottom border td, then scan left until you find name pattern
        # for team a, allway ascend at least 1 row
        tr_elem = prev_td.parent

        # scan tds downward to find the path of bracket based on bottom border style
        while below_td = td_children(tr_elem)[prev_index]
          if below_td.nil?
            raise "Could not find team b in downward pathfinding in bracket for score: #{score_td}"
          end

          # found the bracket path node
          if below_td.attributes['style'] && below_td.attributes['style'].value.match(/border\-bottom/)
            break
          end

          tr_elem = next_tr_elem(tr_elem)
        end

        leftward_td = below_td
        while(!name_pattern_matches?(leftward_td.children.first.to_s))
          leftward_td = previous_td_elem(leftward_td)
          if leftward_td.nil?
            binding.pry
            raise "Could not find team b in leftward pathfinding in bracket for score: #{score_td}"
          end
        end

        leftward_td
      end
    end

    # winning team is always the td element of same index above the score
    def winner(score_td)
      if td_siblings(score_td).size == 1
        score_td = score_td.parent
        while score_td.name != 'td'
          score_td = score_td.parent
        end
      end

      score_index = index_of_td(score_td)
      tr_above = previous_tr_elem(score_td.parent)
      # binding.pry if score_td.children.first.to_s == '11-7,11-7'
      td_children(tr_above)[score_index]
    end


    def all_td
      @document.search("td")
    end

    def all_td_with_text
      all_td.select do |noko_elem|
        noko_elem.children.select { |c| c.is_a?(Nokogiri::XML::Text) }.size > 0
      end
    end

    def all_td_with_score
      all_td_with_text.select do |noko_elem|
        text = noko_elem.children.first.to_s
        text.scan(/[0-9]+\-[0-9]+/).count > 0 && text.scan(/[Ww]ithdrawal/).count == 0
      end
    end

    def all_td_with_long_form_teams
      result = all_td_with_text.select do |noko_elem|
        text = noko_elem.children.first.to_s
        full_name_pattern_matches?(text)
      end

      return result unless result.empty?

      all_td_with_text.select do |noko_elem|
        text = noko_elem.children.first.to_s
        name_pattern_matches?(text)
      end
    end

    def register_teams
      team_tds = all_td_with_long_form_teams

      team_texts = team_tds
        .map{ |score_td| score_td.children.first.to_s.gsub(/\s/, " ") }
        .uniq

      team_texts.each{ |team_td| register_team_2(team_td) }
    end

    # input: "11-9,11-7"
    # output: "[[11, 9], [11,7]]"
    def parsed_scores_from_raw(scores_text)
      scores_text
        .split(',')
        .map{|s| s.split('-').map{ |points| points.to_i } }
    end

    #either position 0 or 1 on the score
    def winner_point_position_in_match(scores)
      games = parsed_scores_from_raw(scores)

      first_more_count = games
        .map{|arr| arr.first - arr.last }
        .select{|diff| diff.positive? }.size

      second_more_count = games
        .map{|arr| arr.last - arr.first }
        .select{|diff| diff.positive? }.size

      first_more_count > second_more_count ? 0 : 1
    end

    def loser_point_position_in_match(scores)
      winner_point_position_in_match(scores) == 0 ? 1 : 0
    end

    private

    # def register_team(team_td)
    #   text = team_td.children.first.to_s
    #   raise "shouldn't register team without first and last names! Team text doesn't match the pattern: #{team}" unless full_name_pattern_matches?(text)
    #   players = text.split('-')
    #
    #   player_a_first = clean_str players.first.split(',').last.gsub(/&nbsp;/, " ")
    #   player_a_last = clean_str players.first.split(',').first.gsub(/&nbsp;/, " ")
    #
    #   player_b_first = clean_str players.last.split(',').last.gsub(/&nbsp;/, " ")
    #   player_b_last = clean_str players.last.split(',').first.gsub(/&nbsp;/, " ")
    #
    #   @teams ||= {}
    #
    #   team = {
    #     player_a_first: player_a_first,
    #     player_a_last: player_a_last,
    #     player_b_first: player_b_first,
    #     player_b_last: player_b_last
    #   }
    #
    #   short_text = "#{player_a_last}-#{player_b_last}"
    #
    #   # register short form of team
    #   @teams[short_text] = {
    #     player_a_first: player_a_first,
    #     player_a_last: player_a_last,
    #     player_b_first: player_b_first,
    #     player_b_last: player_b_last
    #   }
    #
    #   # register longer (first and last name) form of team
    #   @teams[text] = {
    #     player_a_first: player_a_first,
    #     player_a_last: player_a_last,
    #     player_b_first: player_b_first,
    #     player_b_last: player_b_last
    #   }
    #
    #   @teams
    # end


    KNOWN_HYPHEN_FIRST_NAMES = [
      "Pierre-David",
      "Marie-Mediratta",
      "Tienr-X",
      "O-sell"
    ]
    def register_team_2(text)
      @teams ||= {}
      return if @teams[text]
      # raise "shouldn't register team without first and last names! Team text doesn't match the pattern: #{team}" unless full_name_pattern_matches?(text)
      chunks = text.split(',')

      if chunks.count > 1
        # names are long form, don't include last name

        player_a_last = clean_str chunks.shift
        player_b_first = clean_str chunks.pop

        remaining_chunks = chunks.join(',').split('-')

        if remaining_chunks.size > 2
          # This means either player a first has hyphens,
          # Or player b last has hyphens
          # clear up ambiguity by looking up exceptions (kinda hacky, yes)
          ambiguous_chunk = remaining_chunks.join('-')
          if KNOWN_HYPHEN_FIRST_NAMES.select{|exc| ambiguous_chunk.include?(exc) }.any?
            player_b_last = clean_str remaining_chunks.pop
            player_a_first = clean_str remaining_chunks.join('-')
          else
            player_a_first = clean_str remaining_chunks.shift
            player_b_last = clean_str remaining_chunks.join('-')
          end
        else
          player_a_first = clean_str remaining_chunks.shift
          player_b_last = clean_str remaining_chunks.join('-')
        end
      else

        # names are short form, don't include first name
        last_names = chunks.first
        last_names = last_names.split('-')

        player_a_last = last_names.first
        puts "Please enter a first name for #{tournament_name}, #{event_name}, last name: #{player_a_last}"
        player_a_first = STDIN.gets.chomp

        player_b_last = last_names.last
        puts "Please enter a first name for #{tournament_name}, #{event_name}, last name: #{player_b_last}"
        player_b_first = STDIN.gets.chomp
      end



      team = {
        player_a_first: player_a_first,
        player_a_last: player_a_last,
        player_b_first: player_b_first,
        player_b_last: player_b_last
      }

      short_text = "#{player_a_last}-#{player_b_last}"
      longer_text_b = "#{player_a_first} #{player_a_last}-#{player_b_first} #{player_b_last}"

      new_team = {
        player_a_first: player_a_first,
        player_a_last: player_a_last,
        player_b_first: player_b_first,
        player_b_last: player_b_last
      }

      # register short form of team
      @teams[short_text] = new_team

      # register short form of team
      @teams[short_text.to_sym] = new_team

      # register longer (first and last name) form of team
      @teams[text] = new_team

      # register longer (first and last name) form of team
      @teams[text.to_sym] = new_team

      @teams[longer_text_b] = new_team

      @teams[longer_text_b.to_sym] = new_team

      @teams
    end

    def open_tourney_file
      `open #{@io.path}`
    end

    def index_of_td(td_element)
      td_siblings(td_element).index(td_element)
    end

    def td_siblings(td_element)
      td_children(td_element.parent)
    end

    def tr_siblings(tr_element)
      tr_element.parent.children.select do |sibling|
        sibling.is_a?(Nokogiri::XML::Element) && sibling.name === "tr"
      end
    end

    def td_children(tr_element)
      tr_element.children.select do |child|
        child.is_a?(Nokogiri::XML::Element) && child.name === "td"
      end
    end

    def name_pattern_matches?(text)
      text.scan(/[a-zA-Z'\(\) \"\.]+[0-9]*\-[a-zA-Z'\(\) \"\.]+[0-9]*/).count > 0
    end

    def full_name_pattern_matches?(text)
      name_pattern_matches?(text) && text.include?(",")
    end

    def previous_tr_elem(tr_elem)
      res = tr_elem.previous

      if res.nil?
        res = tr_elem
        until res.parent.name == 'tr'
          res = res.parent

          raise "Could not find previous tr element" if res.nil?
        end

        res = res.parent.previous
      end

      return res if res.nil? || res.name === 'tr'

      previous_tr_elem(res)
    end

    def next_tr_elem(tr_elem)
      res = tr_elem.next

      if res.nil?
        res = tr_elem
        until res.parent.name == 'tr'
          res = res.parent
          raise "Could not find previous tr element" if res.nil?
        end

        res = res.parent.next
      end

      return res if res.nil? || res.name === 'tr'

      next_tr_elem(res)
    end

    def previous_td_elem(td_elem)
      res = td_elem.previous
      return res if res.nil? || res.name === 'td'

      previous_td_elem(res)
    end
  end

end
