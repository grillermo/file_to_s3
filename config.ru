require_relative "app"

Process.setproctitle("file_to_s3")
run FileToS3App.new
