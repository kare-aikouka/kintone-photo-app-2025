module KintoneSync
  class File < Base
    def download(file_key)
      res = api.file.get(file_key)
      res
    end

    def upload(params)
      filename = params[:filename]

      res = nil
      Tempfile.create filename, encoding: 'ascii-8bit' do |f|
        f.write(params[:data])
        f.flush
        f.path
        res = api.file.register(f.path, params[:content_type], params[:filename])
      end
      # logger.info "upload: #{res}"
      res
    end
  end
end
