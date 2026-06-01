# frozen_string_literal: true

class ActionLogger < ActiveKintone
  kintone_app_set ENV['APP_ACTION_LOG'], ENV['GUEST_SPACE']
  kintone_record_class_set ActionLogRecord

  class InvalidMessageKey < StandardError; end
  RequestSnapshot = Struct.new(:url, :user_agent, :remote_ip, :referer, keyword_init: true)
  AccountSnapshot = Struct.new(:record, keyword_init: true)
  AccountRecordSnapshot = Struct.new(:email, :group, :company, :team, :area, keyword_init: true)

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
    },
    photos: {
      upload: {
        start: '写真アップロード 開始',
        success: '写真アップロード 成功',
        failure: '写真アップロード 失敗'
      },
      table: {
        update_success: 'サブテーブル 更新成功'
      }
    }
  }.freeze
  UPLOAD_FIELD_LABELS = {
    access_date: %w[アクセス日時],
    user: %w[ログインユーザー],
    action: %w[アクション],
    file_item: %w[ファイル項目 項目],
    number: %w[番号 No NO],
    file_name: %w[ファイル名],
    file_type: %w[ファイル種別 種別],
    file_size: %w[バイト数],
    resized_file_size: %w[リサイズ後バイト数],
    user_agent: %w[端末情報]
  }.freeze

  class << self
    delegate :info, to: :new

    def enabled?
      ENV['APP_ACTION_LOG'].present?
    end

    def upload_enabled?
      ENV['APP_UPLOAD_LOG'].present?
    end

    def photo_upload(key, request:, account:, record_id:, table_code:, file: nil, file_name: nil, content_type: nil, file_size: nil, resized_file_size: nil, row_id: nil, error: nil)
      new.photo_upload(key, request: request, account: account, record_id: record_id, table_code: table_code, file: file, file_name: file_name, content_type: content_type, file_size: file_size, resized_file_size: resized_file_size, row_id: row_id, error: error)
    end

    def photo_upload_async(key, request:, account:, record_id:, table_code:, file: nil, file_name: nil, content_type: nil, file_size: nil, resized_file_size: nil, row_id: nil, error: nil)
      return photo_upload(key, request: request, account: account, record_id: record_id, table_code: table_code, file: file, file_name: file_name, content_type: content_type, file_size: file_size, resized_file_size: resized_file_size, row_id: row_id, error: error) unless upload_enabled?

      request_snapshot = snapshot_request(request)
      account_snapshot = snapshot_account(account)
      run_async do
        photo_upload(key, request: request_snapshot, account: account_snapshot, record_id: record_id, table_code: table_code, file: file, file_name: file_name, content_type: content_type, file_size: file_size, resized_file_size: resized_file_size, row_id: row_id, error: error)
      end
    end

    def photo_table_update_success(request:, account:, record_id:, table_code:)
      new.photo_table_update_success(request: request, account: account, record_id: record_id, table_code: table_code)
    end

    def photo_table_update_success_async(request:, account:, record_id:, table_code:)
      return photo_table_update_success(request: request, account: account, record_id: record_id, table_code: table_code) unless upload_enabled?

      request_snapshot = snapshot_request(request)
      account_snapshot = snapshot_account(account)
      run_async do
        photo_table_update_success(request: request_snapshot, account: account_snapshot, record_id: record_id, table_code: table_code)
      end
    end

    private

    def run_async(&block)
      Thread.new do
        Rails.application.executor.wrap do
          block.call
        rescue StandardError => e
          Rails.logger.warn("ActionLogger async skipped: #{e.class}: #{e.message}")
        end
      end
      nil
    rescue StandardError => e
      Rails.logger.warn("ActionLogger async start skipped: #{e.class}: #{e.message}")
      nil
    end

    def snapshot_request(request)
      RequestSnapshot.new(
        url: request&.url,
        user_agent: request&.user_agent,
        remote_ip: request&.remote_ip,
        referer: request&.referer
      )
    end

    def snapshot_account(account)
      record = account&.record
      AccountSnapshot.new(
        record: AccountRecordSnapshot.new(
          email: record&.email,
          group: record&.group,
          company: record&.company,
          team: record&.team,
          area: record&.area
        )
      )
    end
  end

  def initialize(record_data = nil)
    super
    record.access_date = Time.zone.now.strftime('%F %T.%3N')
  end

  def info(key, request = nil, account = nil)
    return self unless self.class.enabled?

    record.action = message(key)
    assign_request(request) if request
    assign_user(account) if account
    create
    self
  rescue StandardError => e
    Rails.logger.warn("ActionLogger skipped: #{e.class}: #{e.message}")
    self
  end

  def photo_upload(key, request:, account:, record_id:, table_code:, file: nil, file_name: nil, content_type: nil, file_size: nil, resized_file_size: nil, row_id: nil, error: nil)
    return self unless self.class.upload_enabled?

    action = message(key)
    action = "#{action}: #{error.to_s.truncate(120)}" if error.present?
    upload_log_app.create(action_log_record(
      action: action,
      request: request,
      account: account,
      record_id: record_id,
      upload_fields: upload_log_fields(
        table_code: table_code,
        file: file,
        file_name: file_name,
        content_type: content_type,
        file_size: file_size,
        resized_file_size: resized_file_size,
        row_id: row_id
      )
    ))
    self
  rescue StandardError => e
    Rails.logger.warn("ActionLogger photo upload skipped: #{e.class}: #{e.message}")
    self
  end

  def photo_table_update_success(request:, account:, record_id:, table_code:)
    return self unless self.class.upload_enabled?

    action = message('photos.table.update_success')
    upload_log_app.create(action_log_record(
      action: action,
      request: request,
      account: account,
      record_id: record_id,
      upload_fields: upload_log_fields(
        table_code: table_code,
        file_size: 0
      )
    ))
    self
  rescue StandardError => e
    Rails.logger.warn("ActionLogger table update skipped: #{e.class}: #{e.message}")
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

  private

  def action_log_record(action:, request:, account:, record_id:, upload_fields: {})
    fields = {
      access_date: record.access_date,
      user: account&.record&.email,
      action: action,
      url: request&.url,
      app_id: ENV['APP_PHOTOS'].presence || ENV['APP_PHOTO'],
      record_id: record_id,
      group: account&.record&.group,
      company: account&.record&.company,
      team: account&.record&.team,
      area: account&.record&.area,
      user_agent: request&.user_agent,
      referer: request&.referer,
      remote_ip: request&.remote_ip
    }
    fields.merge!(upload_fields)

    fields.each_with_object({}) do |(key, value), result|
      code = field_code_for(key)
      result[code] = { value: value } if code.present? && value.present?
    end
  end

  def upload_log_fields(table_code:, file: nil, file_name: nil, content_type: nil, file_size: nil, resized_file_size: nil, row_id: nil)
    {
      file_item: table_label(table_code),
      number: row_id,
      file_name: file_name || uploaded_file_name(file),
      file_type: content_type || uploaded_file_content_type(file),
      file_size: file_size || uploaded_file_size(file),
      resized_file_size: resized_file_size
    }
  end

  def action_log_properties
    @action_log_properties ||= Rails.cache.fetch(action_log_properties_cache_key, expires_in: 1.hour) do
      kintone_app.properties
    end
  end

  def action_log_properties_cache_key
    [
      "action-log-fields",
      ENV['APP_ACTION_LOG'],
      ENV['GUEST_SPACE']
    ].join(":")
  end

  def upload_log_app
    @upload_log_app ||= KintoneSync::Record.new(ENV['APP_UPLOAD_LOG'], ENV['GUEST_SPACE'])
  end

  def upload_log_properties
    @upload_log_properties ||= Rails.cache.fetch(upload_log_properties_cache_key, expires_in: 1.hour) do
      upload_log_app.properties
    end
  end

  def upload_log_properties_cache_key
    [
      "upload-log-fields",
      ENV['APP_UPLOAD_LOG'],
      ENV['GUEST_SPACE']
    ].join(":")
  end

  def field_code_for(key)
    labels = [ActionLogRecord.key_to_code(key), *UPLOAD_FIELD_LABELS.fetch(key, [])].compact
    upload_log_properties.find { |field_code, property| labels.include?(field_code) || labels.include?(property['label']) }&.first
  rescue StandardError => e
    Rails.logger.warn("ActionLogger field lookup skipped: #{e.class}: #{e.message}")
    nil
  end

  def field_code(code, label = nil)
    return code if code.present?

    labels = Array(label).compact
    action_log_properties.find { |field_code, property| labels.include?(field_code) || labels.include?(property['label']) }&.first
  rescue StandardError => e
    Rails.logger.warn("ActionLogger field lookup skipped: #{e.class}: #{e.message}")
    nil
  end

  def table_label(table_code)
    table_code.to_s.sub(/\Aテーブル/, '').presence || table_code
  end

  def uploaded_file_name(file)
    file.respond_to?(:original_filename) ? file.original_filename : nil
  end

  def uploaded_file_content_type(file)
    file.respond_to?(:content_type) ? file.content_type : nil
  end

  def uploaded_file_size(file)
    return file.size if file.respond_to?(:size)

    nil
  end

end
