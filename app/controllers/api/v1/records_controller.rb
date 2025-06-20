module Api::V1
  class RecordsController < ApiController
    # GET /v1/record
    def show
      params = record_params
      app_id = params['app']
      guest_id = params['guest_id']
      id = params['id']
      logger
      @record = ::KintoneSync::Record.new(app_id, guest_id)
      res = @record.find(id)
      render json: res
    end

    # POST /v1/record
    def create
      params = record_params
      app_id = params['app']
      guest_id = params['guest_id']
      record = params['record']

      @record = ::KintoneSync::Record.new(app_id, guest_id)
      res = @record.create(record)
      render json: res
    end

    # PATCH/PUT /v1/record
    def update
      params = record_params
      app_id = params['app']
      guest_id = params['guest_id']
      id = params['id']
      record = params['record']

      @record = ::KintoneSync::Record.new(app_id, guest_id)
      res = @record.update(id, record)
      render json: res
    end

    # GET /v1/records
    def index
      params = record_params
      app_id = params['app']
      guest_id = params['guest_id']

      query = params['query']
      fields = params['fields']
      total_count = params['totalCount']

      @record = ::KintoneSync::Record.new(app_id, guest_id)
      res = @record.find_list(query: query, fields: fields, total_count: total_count)
      render json: res
    end

    private

    # Only allow a trusted parameter "white list" through.
    def record_params
      params.permit(:app, :guest_id, :id, :query, :totalCount, :format, record: {}, fields: [])
    end
  end
end
