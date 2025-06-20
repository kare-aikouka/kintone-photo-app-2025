# frozen_string_literal: true

ACTION_LOG_RECORD_FIELDS = {
  id: '$id',
  access_date: 'アクセス日時',
  user: 'ログインユーザー',
  action: 'アクション',
  url: 'URL',
  app_id: 'アプリID',
  screen_id: '画面ID',
  record_id: '参照レコード番号',
  group: 'グループ名',
  company: '運用会社名',
  team: '施工班通称',
  area: 'エリア',
  user_agent: '端末情報',
  referer: 'リンク元',
  remote_ip: 'IPアドレス',
}.freeze

class ActionLogRecord < StructRecord.new(ACTION_LOG_RECORD_FIELDS)
end
