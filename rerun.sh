rm results.csv
ruby main.rb $(find ./PB_Tourneys_2020/ | grep htm | tr '\n' ' ')
