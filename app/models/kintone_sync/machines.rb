# app/models/kintone_sync/machines.rb
module KintoneSync
  class Machines < Record
    def app_id
      ENV.fetch("APP_MACHINES", super).to_i
    end
  end
end
