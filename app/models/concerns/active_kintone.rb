# frozen_string_literal: true

class ActiveKintone
  attr_accessor :id, :data, :record
  delegate :kintone_app, :kintone_record_class, to: :class

  def initialize(record_data = nil)
    assign(record_data)
    self.id = record.try(:id).try(:to_i)
  end

  def find(id)
    self.id = id
    assign(kintone_app.find(id)['record'])
    self
  end

  def create(params = nil)
    res = kintone_app.create(params || record.to_params)
    self.id = res['id'].to_i
    record.id = res['id']
  end

  def update(params = nil)
    kintone_app.update(id, params || record.to_params)
  end

  def [](key)
    data[key.to_s].try(:[], 'value')
  end

  def assign(record_data)
    self.data = record_data
    self.record = kintone_record_class.try(:new, record_data)
  end

  def persisted?
    id.present?
  end

  class << self
    def find(id)
      new.find(id)
    end

    def find_by(*cond)
      res = kintone_app.find_by(*cond) or return nil
      new(res)
    end

    def where(*cond)
      kintone_app.where(*cond).map do |record|
        new(record)
      end
    end

    def kintone_app_set(id, guest_space_id = nil)
      @__kintone_app_id = id
      @__kintone_guest_space_id = guest_space_id
    end

    def kintone_app
      @__kintone_app ||= KintoneSync::Record.new(@__kintone_app_id, @__kintone_guest_space_id)
    end

    def kintone_record_class_set(klass)
      @__kintone_record_class = klass
    end

    def kintone_record_class
      @__kintone_record_class
    end
  end
end
