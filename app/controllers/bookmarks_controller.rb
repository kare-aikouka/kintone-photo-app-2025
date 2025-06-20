class BookmarksController < ApplicationController
  before_action :authentication

  def show
    return redirect_to(router_path) unless _user_session
    @page_title = 'ブックマーク登録画面'
  end

  def create
    if request.post?
      self._user_session = nil
      redirect_to router_path
    else
      self._user_session = Time.zone.now.to_i
      logger.debug "_user_session: { instance: '#{_user_session}', session: '#{session[:_user_session]}' }"
      redirect_to bookmark_path
    end
  end

  private
    def _user_session
      session[:_user_session]
    end

    def _user_session= val
      session[:_user_session] = val
    end
end
