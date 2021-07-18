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
  class Singles < Base
    attr_accessor :players

    def self.results(io)
      parser = new(io)

      parser.register_players

      scores = parser.all_td_with_score

      matches = []
      scores.each do |s|
        score_text = s.children.first.to_s

        # skip score being 0 - 0 for forfeit, etc...
        next if score_text.include?('0-0') || score_text.downcase.include?('withdrawal')

        player_a_text = parser.find_player_a(s).children.first.to_s
        player_a_hash = parser.players[player_a_text.to_sym]
        binding.pry if player_a_hash.nil?

        player_b_text = parser.find_player_b(s).children.first.to_s
        player_b_hash = parser.players[player_b_text.to_sym]
        binding.pry if player_b_hash.nil?

        winner_text = parser.winner(s).children.first.to_s
        winner_hash = parser.players[winner_text.to_sym]
        binding.pry if winner_hash.nil?

        winner_score_index = parser.winner_point_position_in_match(score_text)
        loser_score_index = parser.loser_point_position_in_match(score_text)

        player_a_is_winner = winner_hash == player_a_hash
        player_a_score_index = player_a_is_winner ? winner_score_index : loser_score_index
        player_b_score_index = player_a_is_winner ? loser_score_index : winner_score_index

        games = parser.parsed_scores_from_raw(score_text)
        player_a_scores = games.map{ |g| g[player_a_score_index] }
        player_b_scores = games.map{ |g| g[player_b_score_index] }

        matches.push({
          raw_scores: score_text.gsub(/&nbsp;/, " "),
          player_a: player_a_hash,
          player_b: player_b_hash,
          player_a_scores: player_a_scores,
          player_b_scores: player_b_scores,
          winner: winner_hash,
          tournament_name: parser.tournament_name,
          event_name: parser.event_name,
          event_date: parser.event_date
        })
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
          "Player A",
          "Player B",
          "Winning Player",
          "Player A Points Game 1",
          "Player B Points Game 1",
          "Player A Points Game 2",
          "Player B Points Game 2",
          "Player A Points Game 3",
          "Player B Points Game 3",
          "Player A Points Game 4",
          "Player B Points Game 4",
          "Player A Points Game 5",
          "Player B Points Game 5",
          "Player A Points Game 6",
          "Player B Points Game 6"
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

          # player a
          row.push("#{match[:player_a][:first]} #{match[:player_a][:last]}")

          # player b
          row.push("#{match[:player_b][:first]} #{match[:player_b][:last]}")

          # winning player
          row.push("#{match[:winner][:first]} #{match[:winner][:last]}")

          match[:player_a_scores].each_with_index do |score, i|
            row.push(score)
            row.push(match[:player_b_scores][i])
          end

          csv << row
        end
      end
    end

    def initialize(io)
      @io = io
      @document = Nokogiri::HTML(io)
    end

    def find_player_a(score_td)
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
          raise "Could not find player a in upward pathfinding in bracket for score: #{score_td}"
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
          raise "Could not find player a in leftward pathfinding in bracket for score: #{score_td}"
        end
      end

      leftward_td
    end

    def find_player_b(score_td)
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
            raise "Could not find player b in downward pathfinding in bracket for score: #{score_td}"
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
            raise "Could not find player b in leftward pathfinding in bracket for score: #{score_td}"
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

    def all_td_with_long_form_players
      all_td_with_text.select do |noko_elem|
        text = noko_elem.children.first.to_s
        full_name_pattern_matches?(text)
      end
    end

    def register_players
      player_tds = all_td_with_long_form_players

      player_tds.each{ |player_td| register_player(player_td) }
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

    KNOWN_HYPHEN_FIRST_NAMES = [
      "Pierre-David"
    ]

    def register_player(player_td)
      text = player_td.children.first.to_s.gsub(/\s/, " ")
      raise "shouldn't register player without first and last names! Team text doesn't match the pattern: #{text}" unless full_name_pattern_matches?(text)
      chunks = text.split(',')

      player_first = chunks.last
      player_last = chunks.first

      @players ||= {}

      player = {
        first: player_first,
        last: player_last,
      }

      # register short form of team
      @players[text.to_sym] = player

      # register longer (first and last name) form of team
      @players[text] = player

      @players
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
      text.scan(/[a-zA-Z'\(\) \"\.]+[0-9]*/).count > 0
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
