module Tensaku
  # What a note records about the code it was written against: the commit checked out and the origin
  # remote. Read from the files in .git, without running git, and nil when there is no repository.
  module Repo
    module_function

    def head(root)
      git = git_dir(root) or return nil
      ref = git.join("HEAD").read.strip
      return ref if ref.match?(/\A\h{40}\z/)

      name = ref.delete_prefix("ref: ")
      common = common_dir(git)
      [ git, common ].uniq.each do |dir|
        file = dir.join(name)
        return file.read.strip if file.file?
      end
      packed = common.join("packed-refs")
      packed.file? ? packed.each_line.find { it.strip.end_with?(" #{name}") }&.split&.first : nil
    rescue SystemCallError
      nil
    end

    def remote(root)
      git = git_dir(root) or return nil
      config = common_dir(git).join("config")
      return nil unless config.file?

      section = nil
      config.each_line do |line|
        section = line.strip if line.strip.start_with?("[")
        return line.split("=", 2).last.strip if section == '[remote "origin"]' && line.strip.start_with?("url")
      end
      nil
    rescue SystemCallError
      nil
    end

    # The .git directory of root or the nearest folder above it. In a worktree .git is a file that
    # points at it.
    def git_dir(root)
      Pathname(root).expand_path.ascend do |dir|
        dot = dir.join(".git")
        return dot if dot.directory?
        return Pathname(dot.read[/\Agitdir: (.+)$/, 1].to_s.strip).expand_path(dir) if dot.file?
      end
      nil
    rescue SystemCallError
      nil
    end

    def common_dir(git)
      file = git.join("commondir")
      file.file? ? Pathname(file.read.strip).expand_path(git) : git
    end
  end
end
