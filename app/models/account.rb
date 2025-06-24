# frozen_string_literal: true

class Account < ActiveKintone
  kintone_app_set ENV['APP_ACCOUNT'], ENV['GUEST_SPACE']
  kintone_record_class_set AccountRecord

  LOCKED_MIN_COUNT = 10

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
