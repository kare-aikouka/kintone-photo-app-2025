class MachinesController < ApplicationController
  before_action :authentication

  def index
    # Kintone連携のロジック例（kintone_sync等のクラスはプロジェクト固有なのでご自身の環境に合わせて修正）
    @machines = ::KintoneSync::Machines.all  # ←既存のkintone連携クラスを利用
  end
end