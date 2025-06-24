# frozen_string_literal: true

class ActionLogger < ActiveKintone
  kintone_app_set ENV['APP_ACTION_LOG'], ENV['GUEST_SPACE']
  kintone_record_class_set ActionLogRecord

  class InvalidMessageKey < StandardError; end

  MESSAGES = {
    account: {
      success: {
        signed_in: 'ログイン（成功）'
      },
      errors: {
        signed_in_error: 'ログイン失敗（通常）',
        locked_error: 'ログイン失敗（アカウントロック）',
      }
    },
    router: {
      success: {
        employee: '振り分け成功（會澤社員）',
        team: '振り分け成功（施工班）'
      },
    }
  }.freeze

  class << self
    delegate :info, to: :new
  end

  def initialize(record_data = nil)
    super
    record.access_date = Time.zone.now.strftime('%F %T.%3N')
  end

  def info(key, request = nil, account = nil)
    record.action = message(key)
    assign_request(request) if request
    assign_user(account) if account
    create
    self
  end

  def message(key)
    key_params = (key.is_a?(Array) ? key : key.split('.')).map(&:intern)
    MESSAGES.dig(*key_params) or raise InvalidMessageKey, "#{key} に該当するアクションは存在しません"
  end

  def assign_request(request)
    record.referer = request.referer
    record.url = request.url
    record.user_agent = request.user_agent
    record.remote_ip = request.remote_ip
  end

  def assign_user(account)
    record.user = account.record.email
    record.group = account.record.group
    record.company = account.record.company
    record.team = account.record.team
    record.area = account.record.area
  end
end
