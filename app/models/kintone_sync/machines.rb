# app/models/kintone_sync/machines.rb
module KintoneSync
  class Machines < Record
    def app_id
      898 # ←本番環境のkintoneアプリID（ご自身のIDを使ってください）
    end
  end
end
