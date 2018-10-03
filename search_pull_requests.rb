require "net/http"
require "openssl"
require "json"

def http_get_response(uri, *form_data)
  uri = URI.parse(uri)
  http_request = Net::HTTP::Get.new(uri.request_uri)

  http_request[:Authorization] = "token #{TOKEN}"

  http_request.set_form_data(*form_data) if form_data.length > 0

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true if uri.port == 443
  http.request(http_request)
end

def print_bug_header
  BUG_LABELS.each { |bug| printf("%12s|", bug) }
  printf "\n"
end

class Hash
  def print_bug_counts
    self.values.each { |val| printf("%12s|", val) }
    printf "\n"
  end
end

URL_BASE = "https://api.github.com/repos"

REPOSITORIES = File.open("./repositories.txt") do |file|
  file.readlines(chomp: true).delete_if { |line| line.match(/^#/) }
end

valid_lines = File.open("./config") do |file|
  file.readlines(chomp: true).delete_if { |line| line.match(/^#/) }
end

regexp_owner = /^owner=(.+)/i
regexp_token = /^token=(.+)/i
OWNER = valid_lines.grep(regexp_owner).first.match(regexp_owner)[1]
TOKEN = valid_lines.grep(regexp_token).first.match(regexp_token)[1]

BUG_LABELS = %w(
  [style]
  [additional]
  [degrade]
)

initial_bug_counts = {}
BUG_LABELS.each { |bug| initial_bug_counts[bug] = 0 }

all_bug_counts = initial_bug_counts.dup

all_styles = 0
all_additional = 0
all_degrade = 0

hit_pulls = {}
hit_users = {}

puts "プロジェクトキーは?"
board = gets.chomp
return "入力誤り" if board.nil? || board == ""

puts "いつ以降？（yyyy-mm-dd）"
from_date = gets.chomp
return "入力誤り" unless from_date =~ /^20[1-9][0-9]-[0-9]{2}-[0-9]{2}$/

puts "========================================="
puts "#{board}プロジェクトレビューコメントの内容を集計します"
puts "-----------------------------------------"
puts "対象ボード：#{board}"
puts "取得開始日：#{from_date}"
puts "========================================="

REPOSITORIES.each do |repo|
  url = "#{URL_BASE}/#{OWNER}/#{repo}/pulls"
  pulls = JSON.parse(http_get_response(url, state: "all").body)

  pulls.each do |pull|
    title = pull["title"]
    state = pull["state"]
    next unless title =~ /^#{board}/
    next unless state == "open" || pull["merged_at"] >= from_date

    ticket_title = title.match(/^(#{board}-[0-9]+)/)
    ticket_title = ticket_title.length > 1 ? ticket_title[1] : title
    bug_counts = initial_bug_counts.dup

    number = pull["number"]
    url = "#{URL_BASE}/#{OWNER}/#{repo}/pulls/#{number}/comments"
    comments = JSON.parse(http_get_response(url).body)

    comments.each do |comment|
      message = comment["body"]
      BUG_LABELS.each_with_index do |bug, idx|
        bug_counts[bug] += 1 if message.include?(bug)
      end
    end

    if bug_counts.values.sum > 0
      user = pull['user']['login']

      unless hit_pulls.has_key?(repo)
        hit_pulls[repo] = []
      end

      hit_pulls[repo] << {
        ticket: ticket_title,
        created_at: pull['created_at'],
        author: user,
        state: state,
        bugs: bug_counts,
      }

      hit_users[user] = bug_counts
    end

    all_bug_counts.each do |key, val|
      val += bug_counts[key]
    end
  end
end

if hit_pulls.length > 0
  puts "---------------------------------------------"
  puts "プルリクエストごとの集計結果"
  puts "---------------------------------------------"
  hit_pulls.each do |repo_name, pulls|
    puts "** #{repo_name} **"
    printf "%6s|%5s|%19s|%13s|", "チケット", "ステータス", "作成日", "作成者"
    print_bug_header

    pulls.each do |pull|
      printf "%10s|%10s|%22s|%16s|", pull[:ticket], pull[:state], pull[:created_at], pull[:author]
      pull[:bugs].print_bug_counts
    end
  end
end

if hit_users.length > 0
  puts "---------------------------------------------"
  puts "アカウントごとの集計結果"
  puts "---------------------------------------------"
  printf "%10s|", "アカウント"
  print_bug_header
  hit_users.each do |key, val|
    printf "%15s|", key
    val.print_bug_counts
  end
end

printf "%13s|", "合計"
all_bug_counts.print_bug_counts
puts "---------------------------------------------"
