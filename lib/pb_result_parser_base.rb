class PbResultsParser
  class Base
    attr_accessor :io

    NOT_TOURNAMENT_NAMES = [
      "Winner Top Half",
      "Winner Bottom Half",
      "Loser Top Half",
      "Loser Bottom Half",
      "Winners Bracket",
      "Losers Bracket",
      "Tournaments"
    ]

    EVENT_ACRONYMS = [
      "WD",
      "MD",
      "MS",
      "WS",
      "MXD",
      "WDO",
      "MDS",
      "WDS",
      "MDSP",
      "MXDO",
      "MDO",
      "WDSP",
      "MXDSSP",
      "WPD",
      "SMPD",
      "MXDP",
      "MPD",
      "SWPD",
      "SMXD",
      "WDP",
      "MDP",
      "MXDS",
      "WPS",
      "MPS",
      "MSPS",
      "MSP",
      "MXDPS",
      "MXDSP",
      "WSPS",
      "MXSD",
      "WSSO",
      "MSDO",
      "MSSO",
      "MXSDO",
      "MSO",
      "WSDO",
      "WSO"
    ]

    def tournament_name
      return @tournament_name if @tournament_name

      all_headers = @document.search("h2") + @document.search("h3") + @document.search("h4")

      possible_tourney_name_headers = all_headers.select{|header| !NOT_TOURNAMENT_NAMES.include?(header.children.first.to_s) }
      binding.pry if possible_tourney_name_headers.empty?
      # binding.pry if event_date == "12/05/20"
      @tournament_name ||= possible_tourney_name_headers.first.children.first.to_s
      # @tournament_name ||= @document.search("h3")&.first&.children&.first&.to_s
      # @tournament_name ||= @document.search("h4").first.children.first.to_s
    end

    def event_name
      return @event_name if @event_name

      all_headers = @document.search("h2") +
        @document.search("h3") +
        @document.search("h4")

      possible_event_name_headers = all_headers.select do |header|
        !header.children.select do |child|
          child.to_s.match(/Singles|Doubles/) ||
            child.to_s.match(/Men|Women|Mixed/) ||
            child.to_s.match(Regexp.new(EVENT_ACRONYMS.join('|')))
        end.empty?
      end

      # binding.pry if event_date == "12/05/20"

      binding.pry if possible_event_name_headers.empty?

      @event_name = possible_event_name_headers.first.children.last.to_s
      # @event_name = @document.search("h2")&.first&.children&.last&.to_s
      # @event_name ||= @document.search("h3")&.first&.children&.last&.to_s
      # @event_name ||= @document.search("h4").first.children.last.to_s
    end

    def event_date
      # last italic in the doc,
      # last child, assuming the date in the certain pos. Pretty brittle
      @event_date ||= @document.search("i").last.children.first.to_s.split(" ")[-2]
    end
  end
end
