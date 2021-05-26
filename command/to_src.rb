def to_src(file_name)
  after = ''
  File.open(file_name) do |file|
    file.each_line do |line|
      after << line.gsub(/^(!)?\/?([\w.\/*\-]+)$/, '\1src/\2')
    end
  end
  f = File.open(file_name, 'w')
  f.puts after
  f.close
  after
end
