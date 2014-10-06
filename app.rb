require 'redis'
require 'mechanize'
require 'yaml'

class FlNotifications

  def initialize(config)
    @redis = Redis.new
    @browser = Mechanize.new do |c|
      c.user_agent = config['user_agent']
    end

    @queries = config['queries']
    @send_sms_to = config['send_sms_to']
    @sms_ru_token = config['sms_ru_token']

    unless auth(config['login'], config['password'])
      puts 'Не удалось авторизоваться.'
      exit
    end
  end

  def send_notifications
    @queries.each do |query|
      projects(query).each do |project|
        key = "fl_notifucations:projects:#{project[:id]}"
        title = project[:title].length > 59 ? 'fl.ru: ' + project[:title][0..59] + ' ...' : 'fl.ru: ' + project[:title]
        unless @redis.exists(key)
          @redis.set(key, send_sms(@send_sms_to, title))
        end
      end
    end
  end

  private

    def auth(login, password)
      page = @browser.get('http://www.fl.ru/registration/')
      form = page.form_with(id: 'login_form')
      form.login = login
      form.passwd = password
      page = form.submit

      page.body.scan('b-user-menu').any?
    end

    def projects(query)
      page = @browser.get('http://www.fl.ru/projects/?kind=1')
      form = page.form_with(id: 'frm')
      form.pf_keywords = query
      form.add_field!('u_token_key', page.body.scan(/var U_TOKEN_KEY = "([0-9a-z]+)";/).first.first)
      page = form.submit

      page.root.css('.b-post').map do |post|
        {
          id: post['id'].sub('project-item', '').to_i,
          title: post.css('.b-post__title > a').text.strip
        }
      end
    end

    def send_sms(to, message)
      url = 'http://sms.ru/sms/send'
      params = {
        api_id: @sms_ru_token,
        to: to,
        text: message
      }

      page = @browser.get(url + '?' + params.collect { |k,v| "#{k}=#{URI::encode(v)}"}.join('&'))
      page.body.split[0] == '100'
    end
end

config = YAML.load(File.open('./config.yml', 'r').read)
FlNotifications.new(config).send_notifications