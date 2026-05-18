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
  UPLOAD_TABLE_LABEL = 'アップロードリスト'
  UPLOAD_FIELD_LABELS = {
    access_date: %w[アクセス日時],
    user: %w[ログインユーザー],
    action: %w[アクション],
    file_item: %w[ファイル項目 項目],
    number: %w[番号 No NO],
    file_name: %w[ファイル名],
    file_type: %w[ファイル種別 種別],
    file_size: %w[ファイルサイズ サイズ],
    user_agent: %w[端末情報]
  }.freeze

  class << self
    delegate :info, to: :new

    def enabled?
      ENV['APP_ACTION_LOG'].present?
    end

    def photo_upload(key, request:, account:, record_id:, table_code:, file: nil, file_name: nil, content_type: nil, file_size: nil, row_id: nil, error: nil)
      new.photo_upload(key, request: request, account: account, record_id: record_id, table_code: table_code, file: file, file_name: file_name, content_type: content_type, file_size: file_size, row_id: row_id, error: error)
    end

    def photo_table_update_success(request:, account:, record_id:, table_code:)
      new.photo_table_update_success(request: request, account: account, record_id: record_id, table_code: table_code)
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

  def photo_upload(key, request:, account:, record_id:, table_code:, file: nil, file_name: nil, content_type: nil, file_size: nil, row_id: nil, error: nil)
    return self unless self.class.enabled?

    action = message(key)
    action = "#{action}: #{error.to_s.truncate(120)}" if error.present?
    create(action_log_record(
      action: action,
      request: request,
      account: account,
      record_id: record_id,
      upload_rows: [
        upload_log_row(
          action: action,
          account: account,
          table_code: table_code,
          file: file,
          file_name: file_name,
          content_type: content_type,
          file_size: file_size,
          row_id: row_id,
          request: request
        )
      ]
    ))
    self
  rescue StandardError => e
    Rails.logger.warn("ActionLogger photo upload skipped: #{e.class}: #{e.message}")
    self
  end

  def photo_table_update_success(request:, account:, record_id:, table_code:)
    return self unless self.class.enabled?

    action = message('photos.table.update_success')
    create(action_log_record(
      action: action,
      request: request,
      account: account,
      record_id: record_id,
      upload_rows: [
        upload_log_row(
          action: action,
          account: account,
          table_code: table_code,
          file_size: 0,
          request: request
        )
      ]
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

  def action_log_record(action:, request:, account:, record_id:, upload_rows: [])
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

    payload = fields.each_with_object({}) do |(key, value), result|
      code = field_code(ActionLogRecord.key_to_code(key), ActionLogRecord.key_to_code(key))
      result[code] = { value: value } if code.present? && value.present?
    end

    table_code = upload_table_code
    payload[table_code] = { value: upload_rows } if table_code.present? && upload_rows.present?
    payload
  end

  def upload_log_row(action:, account:, table_code:, request:, file: nil, file_name: nil, content_type: nil, file_size: nil, row_id: nil)
    row_fields = {
      access_date: record.access_date,
      user: account&.record&.email,
      action: action,
      file_item: table_label(table_code),
      number: row_id,
      file_name: file_name || uploaded_file_name(file),
      file_type: content_type || uploaded_file_content_type(file),
      file_size: megabytes(file_size || uploaded_file_size(file)),
      user_agent: request&.user_agent
    }

    {
      value: row_fields.each_with_object({}) do |(key, value), result|
        code = upload_subfield_code(key)
        result[code] = { value: value } if code.present? && value.present?
      end
    }
  end

  def action_log_properties
    @action_log_properties ||= kintone_app.properties
  end

  def field_code(code, label = nil)
    return code if code.present?

    labels = Array(label).compact
    action_log_properties.find { |field_code, property| labels.include?(field_code) || labels.include?(property['label']) }&.first
  rescue StandardError => e
    Rails.logger.warn("ActionLogger field lookup skipped: #{e.class}: #{e.message}")
    nil
  end

  def upload_table_code
    @upload_table_code ||= action_log_properties.find do |field_code, property|
      field_code == UPLOAD_TABLE_LABEL || property['label'] == UPLOAD_TABLE_LABEL
    end&.first
  rescue StandardError => e
    Rails.logger.warn("ActionLogger upload table lookup skipped: #{e.class}: #{e.message}")
    nil
  end

  def upload_subfield_code(key)
    table_code = upload_table_code
    return if table_code.blank?

    fields = action_log_properties.dig(table_code, 'fields') || {}
    labels = UPLOAD_FIELD_LABELS.fetch(key, [])
    fields.find { |field_code, property| labels.include?(field_code) || labels.include?(property['label']) }&.first
  rescue StandardError => e
    Rails.logger.warn("ActionLogger upload field lookup skipped: #{e.class}: #{e.message}")
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

  def megabytes(bytes)
    return if bytes.blank?

    (bytes.to_f / 1.megabyte).round(2)
  end
end
