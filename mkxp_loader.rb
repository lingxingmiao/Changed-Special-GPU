# ============================================================================
#  mkxp-z RGSS2 (RPG Maker VX) 兼容加载器
#
#  作用：让一批老国产 RGSS2 游戏能在 mkxp-z 上正常运行（从而吃到 GPU 渲染）。
#  它不修改任何游戏文件，全部修复都在运行时内存里完成。
#
#  解决的四个问题：
#   1) mkxp-z 自身的 Data/Scripts.rvdata 加载流程对这类游戏不生效
#      （表现为：窗口黑屏、脚本从不执行、几秒后自己退出）
#      → 本加载器手动读取 + 解压 + 按顺序 eval，等效 RGSS 的脚本加载流程
#   2) 老脚本里 Ruby 1.8 才认的写法（如 `if cond:` 结尾带冒号）
#      在 mkxp-z 的 Ruby 3.x 下是语法错误 → eval 前做一次文本兼容转换
#   3) 「截图存档」类脚本用 Win32API + RtlMoveMemory 按 Ruby 1.8 的对象布局
#      （object_id * 2 + 16）直接读写 Bitmap 内存，Ruby 3.x 下 object_id 已不是
#      地址 → 往野地址写数据直接段错误（读档必崩）
#      → eval 后检测并覆盖 Bitmap#_dump / Bitmap._load，改用 raw_data
#        （没有 raw_data 时回退 get_pixel/set_pixel），存档数据结构不变
#   4) mkxp-z 里 Input::A 默认没有绑到 Shift，而 RGSS 原版的 A 键（疾跑、
#      对话瞬间显示、菜单快捷键）就是 Shift → 在引擎层把 Shift 映射成 Input::A
#      另外把引擎的 F12（mkxp-z 会直接抛 Reset 关掉游戏）接住，改成"回标题画面"
#
#  用法：把这个文件和 mkxp.json 放进游戏目录（与 Game.exe 同级），
#        启动 mkxp-z.exe 即可。日志写在 dsh_log.txt。
# ============================================================================

DSH_LOG_FILE = "dsh_log.txt"

def dsh_log(m)
  begin
    File.open(DSH_LOG_FILE, "a") { |f| f.puts("#{Time.now.strftime('%H:%M:%S')} #{m}") }
  rescue Exception
  end
end

dsh_log("=== mkxp-z RGSS2 兼容加载器启动 (ruby #{RUBY_VERSION}) ===")

# ---------------------------------------------------------------------------
# 1) Ruby 1.8 → Ruby 3.x 语法兼容（只动行尾多余的冒号）
# ---------------------------------------------------------------------------
DSH_RUBY18_PATTERN = /^([ \t]*(?:if|unless|while|until|for|case|when)\b.*[^:])[ \t]*:[ \t]*\r?$/

def dsh_fix_ruby18(src)
  src.gsub(DSH_RUBY18_PATTERN) { $1 }
end

# ---------------------------------------------------------------------------
# 2) Bitmap 序列化兼容（老式内存 hack → raw_data / get_pixel）
# ---------------------------------------------------------------------------
def dsh_patch_bitmap_marshal
  return if $__dsh_bitmap_patched
  begin
    return unless defined?(Bitmap)
    return unless Bitmap.method_defined?(:address)      # 老式内存 hack 的标志
  rescue Exception
    return
  end
  Bitmap.class_eval do
    def _dump(limit)
      data = nil
      begin
        data = raw_data if respond_to?(:raw_data)
      rescue Exception
        data = nil
      end
      if data.nil? || data.length != width * height * 4
        buf = ""
        y = 0
        while y < height
          x = 0
          while x < width
            c = get_pixel(x, y)
            buf << [c.red, c.green, c.blue, c.alpha].pack("C4")
            x += 1
          end
          y += 1
        end
        data = buf
      end
      [width, height, Zlib::Deflate.deflate(data)].pack("LLa*")
    end

    def self._load(str)
      w, h, zdata = str.unpack("LLa*")
      b = new(w, h)
      raw = Zlib::Inflate.inflate(zdata)
      return b if raw.nil? || raw.empty?
      done = false
      begin
        if b.respond_to?(:raw_data=) && raw.length == w * h * 4
          b.raw_data = raw
          done = true
        end
      rescue Exception
        done = false
      end
      unless done
        i = 0
        y = 0
        while y < h
          x = 0
          while x < w
            r  = raw[i].ord
            g  = raw[i + 1].ord
            bl = raw[i + 2].ord
            a  = raw[i + 3].ord
            b.set_pixel(x, y, Color.new(r, g, bl, a))
            i += 4
            x += 1
          end
          y += 1
        end
      end
      return b
    end
  end
  $__dsh_bitmap_patched = true
  dsh_log("已启用 Bitmap 内存 hack 兼容补丁（_dump/_load 改走 raw_data）")
end

# ---------------------------------------------------------------------------
# 3) Shift → Input::A（RGSS 原版里 A 键就是 Shift）
# ---------------------------------------------------------------------------
module Input
  DSH_A_CODES = [0xA0, 0xA1, 0x10, :LSHIFT, :RSHIFT, :SHIFT]

  def self.dsh_shift_down?
    DSH_A_CODES.each do |k|
      begin
        return true if pressex?(k)
      rescue Exception
      end
    end
    return false
  end

  class << self
    unless method_defined?(:__dsh_update)
      alias_method :__dsh_update, :update
      def update(*a)
        $__dsh_shift_prev = $__dsh_shift_now
        $__dsh_shift_now  = Input.dsh_shift_down?
        __dsh_update(*a)
      end

      alias_method :__dsh_press?, :press?
      def press?(key)
        return true if key == Input::A && $__dsh_shift_now
        __dsh_press?(key)
      end

      alias_method :__dsh_trigger?, :trigger?
      def trigger?(key)
        return true if key == Input::A && $__dsh_shift_now && !$__dsh_shift_prev
        __dsh_trigger?(key)
      end

      alias_method :__dsh_repeat?, :repeat?
      def repeat?(key)
        return true if key == Input::A && $__dsh_shift_now
        __dsh_repeat?(key)
      end
    end
  end
end
dsh_log("已启用 Shift → Input::A 映射")

# ---------------------------------------------------------------------------
# 4) 帧率日志 + F12 返回标题画面
# ---------------------------------------------------------------------------
class << Graphics
  unless method_defined?(:__dsh_update_g)
    alias_method :__dsh_update_g, :update
  end
  def update(*args)
    __dsh_update_g(*args)

    f12 = begin
      Input.pressex?(0x7B)
    rescue Exception
      false
    end
    if f12 && !$__dsh_f12_prev
      begin
        if defined?($scene) && $scene && $scene.class.to_s != "Scene_Title"
          dsh_log("F12 → 返回标题画面（当前 #{$scene.class}）")
          $scene = Scene_Title.new
        end
      rescue Exception => e
        dsh_log("F12 处理失败 #{e.class}: #{e.message}")
      end
    end
    $__dsh_f12_prev = f12

    $__dsh_frames = ($__dsh_frames || 0) + 1
    t = Time.now.to_f
    $__dsh_t0 ||= t
    if t - $__dsh_t0 >= 1.0
      sc = (defined?($scene) && $scene) ? $scene.class.to_s : "-"
      dsh_log("fps=#{$__dsh_frames}  场景=#{sc}") if sc != $__dsh_scene
      $__dsh_scene = sc
      $__dsh_frames = 0
      $__dsh_t0 = t
    end
  end
end

at_exit do
  dsh_log("=== 退出 (frames=#{defined?(Graphics) ? Graphics.frame_count : '?'}) #{$!.inspect} ===")
end

# ---------------------------------------------------------------------------
# 5) 脚本加载（可重复执行：F12/Reset → 重新加载 → 回到标题画面）
# ---------------------------------------------------------------------------
def dsh_script_path
  path = "Data/Scripts.rvdata"
  begin
    ini = File.open("Game.ini", "rb") { |f| f.read }
    if ini =~ /Scripts\s*=\s*(.+)/
      v = $1.strip
      path = v.tr("\\", "/") unless v.empty?
    end
  rescue Exception
  end
  path
end

def dsh_load_scripts
  path = dsh_script_path
  arr = Marshal.load(File.open(path, "rb") { |f| f.read })
  dsh_log("读取 #{path} 成功，#{arr.size} 个脚本")
  n_ok = 0
  arr.each do |e|
    id = e[0]; name = (e[1].to_s rescue "?"); code = e[2]
    next if code.nil? || code.to_s.empty?
    begin
      src = Zlib::Inflate.inflate(code)
    rescue Exception => ex
      dsh_log("解压失败 #{id}:#{name} #{ex.class}: #{ex.message}")
      next
    end
    src = dsh_fix_ruby18(src)
    begin
      eval(src, TOPLEVEL_BINDING, "#{id}:#{name}")
      n_ok += 1
    rescue SystemExit
      raise
    rescue Exception => ex
      raise if ex.class.to_s == "Reset"     # mkxp-z 的 F12 重置信号，交给外层
      dsh_log("脚本出错 #{id}:#{name} #{ex.class}: #{ex.message}")
      ((ex.backtrace rescue nil) || [])[0, 6].each { |l| dsh_log("      #{l}") }
    end
    dsh_patch_bitmap_marshal
  end
  dsh_log("脚本加载完成，成功 #{n_ok} 个")
end

loop do
  begin
    dsh_load_scripts
    break
  rescue Exception => e
    if e.is_a?(SystemExit) || e.class.to_s == "Reset"
      dsh_log("收到重置信号（#{e.class}，F12）→ 清理场景并重新加载脚本，回到标题画面")
      begin
        if defined?($scene) && $scene
          $scene.terminate if $scene.respond_to?(:terminate)
          $scene.dispose   if $scene.respond_to?(:dispose)
        end
      rescue Exception
      end
      begin
        $scene = nil
        Graphics.transition(0)
      rescue Exception
      end
      next
    else
      dsh_log("加载器失败: #{e.class}: #{e.message}")
      ((e.backtrace rescue nil) || [])[0, 10].each { |l| dsh_log("      #{l}") }
      break
    end
  end
end
