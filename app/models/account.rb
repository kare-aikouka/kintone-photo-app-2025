# frozen_string_literal: true

require 'json'

class Account < ActiveKintone
  kintone_app_set ENV['APP_ACCOUNT'], ENV['GUEST_SPACE']
  kintone_record_class_set AccountRecord

  LOCKED_MIN_COUNT = 10
  LOCAL_ACCOUNT_ID_PREFIX = 'local-account'
  LocalRecord = Struct.new(
    :id,
    :area,
    :eigyosyo,
    :user,
    :team,
    :email,
    :password,
    :group,
    :company,
    :status,
    :fail_count,
    keyword_init: true
  )

  class AccountError < StandardError; end
  class LockedError < AccountError; end
  class SignedInError < AccountError; end

  class << self
    #
    # 仕様
    # - 存在するアカウントに対して10回ログインに失敗したら、ロックする
    # - ログインに成功したらロックカウントは0に戻る
    # - ステータスが無効なアカウントに対しては、正しいパスワードを入れたとしても失敗と扱う
    #
    def sign_in(email:, password:)
      return local_sign_in(email: email, password: password) if local_auth?

      email_code = kintone_record_class.key_to_code(:email)
      account = find_by(email_code => email) or raise SignedInError
      if account.validate(password)
        account.resetFailCount
        return account
      end
      account.incrementFailCount
      raise LockedError if account.locked?
      raise SignedInError
    end

    def find(id)
      if local_auth?
        record = local_accounts.find { |account| account.id.to_s == id.to_s }
        return local_account(record || local_accounts.first) if record || local_account_id?(id)
      end

      super
    end

    private

    def local_sign_in(email:, password:)
      record = local_accounts.find do |account|
        secure_compare(account.email, email) && secure_compare(account.password, password)
      end
      raise SignedInError unless record

      local_account(record)
    end

    def local_auth?
      local_accounts.any?
    end

    def local_account_id?(id)
      id.to_s == LOCAL_ACCOUNT_ID_PREFIX || id.to_s.start_with?("#{LOCAL_ACCOUNT_ID_PREFIX}-")
    end

    def local_account(record)
      new.tap do |account|
        account.id = record.id
        account.record = record
        account.data = {}
      end
    end

    def local_accounts
      @local_accounts ||= configured_local_accounts
    end

    def configured_local_accounts
      account_configs = json_local_account_configs.presence || numbered_local_account_configs
      account_configs << single_local_account_config if account_configs.empty? && single_local_account_config

      account_configs.each_with_index.filter_map do |config, index|
        email = config[:email].to_s.strip.presence
        password = config[:password].to_s
        next if email.blank? || password.blank?

        LocalRecord.new(
          id: "#{LOCAL_ACCOUNT_ID_PREFIX}-#{index + 1}",
          area: config[:area],
          eigyosyo: config[:eigyosyo],
          user: email,
          team: config[:team],
          email: email,
          password: password,
          group: config[:group].presence || '會澤社員',
          company: config[:company],
          status: '有効',
          fail_count: 0
        )
      end
    end

    def json_local_account_configs
      raw = ENV['APP_ACCOUNTS'].to_s.strip
      return [] if raw.blank?

      parsed = JSON.parse(raw)
      accounts = parsed.is_a?(Hash) && parsed['accounts'].is_a?(Array) ? parsed['accounts'] : Array(parsed)
      accounts.map do |account|
        next {} unless account.is_a?(Hash)

        {
          email: account['email'] || account['account'] || account['id'],
          password: account['password'],
          group: account['group'],
          team: account['team'],
          area: account['area'],
          company: account['company'],
          eigyosyo: account['eigyosyo']
        }
      end
    rescue JSON::ParserError => e
      Rails.logger.warn("APP_ACCOUNTS ignored: #{e.class}: #{e.message}")
      []
    end

    def numbered_local_account_configs
      (1..20).filter_map do |index|
        email = ENV["APP_ACCOUNT_#{index}"].presence || ENV["APP_LOGIN_ID_#{index}"].presence
        password = ENV["APP_PASSWORD_#{index}"].presence || ENV["APP_LOGIN_PASSWORD_#{index}"].presence
        next if email.blank? && password.blank?

        {
          email: email,
          password: password,
          group: ENV["APP_ACCOUNT_GROUP_#{index}"],
          team: ENV["APP_ACCOUNT_TEAM_#{index}"],
          area: ENV["APP_ACCOUNT_AREA_#{index}"],
          company: ENV["APP_ACCOUNT_COMPANY_#{index}"],
          eigyosyo: ENV["APP_ACCOUNT_EIGYOSYO_#{index}"]
        }
      end
    end

    def single_local_account_config
      email = ENV['APP_LOGIN_ID'].presence || ENV['LOGIN_EMAIL'].presence || non_numeric_app_account
      password = ENV['APP_PASSWORD'].presence || ENV['APP_LOGIN_PASSWORD'].presence || ENV['LOGIN_PASSWORD'].presence
      return if email.blank? && password.blank?

      {
        email: email,
        password: password,
        group: ENV['APP_ACCOUNT_GROUP'],
        team: ENV['APP_ACCOUNT_TEAM'],
        area: ENV['APP_ACCOUNT_AREA'],
        company: ENV['APP_ACCOUNT_COMPANY'],
        eigyosyo: ENV['APP_ACCOUNT_EIGYOSYO']
      }
    end

    def non_numeric_app_account
      value = ENV['APP_ACCOUNT'].to_s.strip
      value.presence unless value.match?(/\A\d+\z/)
    end

    def secure_compare(expected, actual)
      expected = expected.to_s
      actual = actual.to_s
      return false if expected.blank? || actual.blank?
      return false unless expected.bytesize == actual.bytesize

      ActiveSupport::SecurityUtils.secure_compare(expected, actual)
    end
  end

  def group_employee?
    record.group == '會澤社員'
  end

  def group_team?
    record.group == '施工班'
  end

  def validate(password)
    record.password == password && enabled? && unlocked?
  end

  def enabled?
    record.status == '有効'
  end

  def locked?
    record.fail_count >= LOCKED_MIN_COUNT
  end

  def unlocked?
    !locked?
  end

  def resetFailCount
    return if record.fail_count == 0
    record.fail_count = 0
    update
  end

  def incrementFailCount
    record.fail_count += 1
    update
  end

  def data_without_password
    data.reject { |k, _| k == 'パスワード' }
  end

  module Helper
    def current_account
      @__account ||= Account.find(session[:account_id]) if signed_in?
    end

    def signed_in?
      session[:account_id].present?
    end
  end
end
