# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :redirect_if_already_signed_in, only: :sign_in

  def sign_in
    @page_title = 'ログイン画面'
    @email = ''
    @backto = params[:backto]
    @account = Account.new
  end

  def session_create
    @email = params[:email]
    backto_path = build_backto_path
    account = Account.sign_in(email: params[:email], password: params[:password])
    session[:account_id] = account.id
    ActionLogger.info('account.success.signed_in', request, account)
    if backto_path.present?
      redirect_to backto_path
    else
      redirect_to router_path
    end
  rescue Account::AccountError => e
    error_key = e.class.name.underscore.split('/').last
    flash.now[:danger] = I18n.t(error_key, scope: 'flash.errors')
    account = Account.new
    account.record.email = @email
    ActionLogger.info([:account, :errors, error_key], request, account)
    render :sign_in
  end

  def session_destroy
    session.delete :account_id
    redirect_to sign_in_path
  end

  private

  def redirect_if_already_signed_in
    redirect_to router_path if signed_in?
  end

  def build_backto_path
    @backto = params[:backto]
    @hashbang = params[:hashbang]
    "#{@backto}#{@hashbang}"
  end
end
