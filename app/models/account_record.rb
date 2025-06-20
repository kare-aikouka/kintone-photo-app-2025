# frozen_string_literal: true

ACCOUNT_RECORD_FIELDS = {
  id: '$id',
  area: 'エリア',
  eigyosyo: '管轄営業所',
  user: 'ログイン名称',
  team: '施工班通称',
  email: 'メールアドレス',
  password: 'パスワード',
  group: 'グループ名',
  company: '運用会社名',
  status: 'status',
  fail_count: '失敗カウント',
}.freeze

class AccountRecord < StructRecord.new(ACCOUNT_RECORD_FIELDS)
  def fail_count
    super.to_i # 未設定時の nil を考慮
  end
end
