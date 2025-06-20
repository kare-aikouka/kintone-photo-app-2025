# frozen_string_literal: true

# :reek:ModuleInitialize
module StructRecord
  module_function

  class FieldNotFound < StandardError; end
  class InvalidFileFormat < StandardError; end

  def self.grant_value_to_params
    true
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/BlockLength
  def new(maps)
    Class.new(Struct.new(*maps.keys)) do
      const_set :MAPS, maps

      def self.file_fields(*keys)
        if keys.empty?
          if class_variable_defined?(:@@file_fields)
            return class_variable_get(:@@file_fields)
          end
          return []
        end
        class_variable_set :@@file_fields, keys.map(&:intern)
      end

      def initialize(record = nil)
        super()
        return unless record
        self.record = record
        assign_fields
      end

      def self.key_to_code(key)
        self::MAPS[key]
      end

      def self.keys_to_codes(*keys)
        keys.flatten.map { |key| key_to_code(key) }
      end

      def key_to_code(key)
        self.class::MAPS[key]
      end

      def each_pair
        members.each do |key|
          yield key, send(key)
        end
      end

      delegate :present?, :blank?, to: :record

      # TODO: exclude オプションで展開しないキーを指定する
      # 例えば、新規作成時には保存したくないパラメータがある場合（kintone 側で初期値があるやつ）
      # nil のまま保存すると支障が出る場合があるので、そういう項目は出力したくない
      def to_params
        result = {}
        each_pair do |key, value|
          begin
            norm_value = normalize_value(key, value)
            result[key_to_code(key)] =
              StructRecord.grant_value_to_params ? { value: norm_value } : norm_value
          rescue InvalidFileFormat
            next
          end
        end
        result
      end

      private

      attr_accessor :record

      def file_fields
        klass = self.class
        if klass.class_variable_defined?(:@@file_fields)
          klass.class_variable_get(:@@file_fields)
        else
          []
        end
      end

      def normalize_value(key, value)
        return value unless file_fields.include?(key.intern)
        return value if value.is_a?(Array)
        # FILE フィールドに対して配列以外を渡すと KintoneSync がフリーズする
        raise InvalidFileFormat
      end

      def assign_fields
        self.class::MAPS.each do |key, field_code|
          self[key] = record_value(field_code)
        end
      end

      def record_value(name)
        cast_value_by_type(name)
      end

      def cast_value_by_type(name)
        hash = record[name]
        unless hash
          raise FieldNotFound, "kintone のアプリ内に #{name} というフィールドコードが見つかりませんでした"
        end
        value = hash['value']
        case record[name]['type']
        when 'NUMBER', 'CALC'
          return nil if value.blank?
          if value.include?('.')
            value.to_f
          else
            value.to_i
          end
        when 'DATE'
          value.try(:to_date)
        when 'DATETIME'
          value.try(:in_time_zone)
        else
          value
        end
      end

      def zenkaku_num_to_hankaku(str)
        str.tr('０-９', '0-9')
      end
    end
  end
end
