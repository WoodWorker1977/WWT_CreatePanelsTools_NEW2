require 'sketchup.rb'
require 'extensions.rb'
require 'net/http'
require 'json'
require 'fileutils'

module WWT_CreatePanelsTools
  VERSION = "1.8.5"  # Оновлено версію до 1.8.5

  # Константи для шляхів
  PLUGIN_ROOT = File.dirname(__FILE__)
  PLUGIN_DIR = File.join(PLUGIN_ROOT, 'WWT_CreatePanelsTools')
  ICONS_DIR = File.join(PLUGIN_DIR, 'ico')
  TEXTURES_DIR = File.join(PLUGIN_DIR, 'Texturs')
  SETTINGS_DIR = File.join(PLUGIN_DIR, 'settings')
  SETTINGS_FILE = File.join(SETTINGS_DIR, 'plugin_settings.json')
    
  # Змінна для відстеження стану кнопки матеріалів
  @materials_button_state = true
  @cmd_materials_handler = nil

  # Метод для збереження налаштувань
  def self.save_settings
    settings = {
      'materials_button_state' => @materials_button_state,
      'last_modified' => Time.now.strftime("%Y-%m-%d %H:%M:%S"),
      'last_user' => ENV['USERNAME'] || 'Unknown'
    }
    
    begin
      FileUtils.mkdir_p(SETTINGS_DIR) unless Dir.exist?(SETTINGS_DIR)
      File.write(SETTINGS_FILE, JSON.pretty_generate(settings))
      puts "Налаштування збережено в: #{SETTINGS_FILE}"
      puts "Поточний стан кнопки: #{@materials_button_state}"
      puts "Вміст файлу налаштувань:"
      puts File.read(SETTINGS_FILE)
    rescue StandardError => e
      puts "Помилка збереження налаштувань: #{e.message}"
      puts e.backtrace
    end
  end
  
  # Метод для завантаження налаштувань
  def self.load_settings
    if File.exist?(SETTINGS_FILE)
      begin
        settings = JSON.parse(File.read(SETTINGS_FILE))
        if settings.has_key?('materials_button_state')
          @materials_button_state = settings['materials_button_state']
          puts "Налаштування завантажено. Стан кнопки встановлено в: #{@materials_button_state}"
        else
          puts "У файлі налаштувань відсутній параметр 'materials_button_state'"
          @materials_button_state = true # значення за замовчуванням
        end
      rescue StandardError => e
        puts "Помилка завантаження налаштувань: #{e.message}"
        @materials_button_state = true # значення за замовчуванням
      end
    else
      puts "Файл налаштувань не знайдено. Використовується значення за замовчуванням."
      @materials_button_state = true # значення за замовчуванням
    end
  end

  # Метод для оновлення шляхів у JSON файлі
  def self.update_json_paths
    json_path = File.join(SETTINGS_DIR, "panel_defaults.json")
    return unless File.exist?(json_path)

    begin
      puts "Оновлення шляхів у JSON файлі..."
      
      # Читаємо JSON файл
      json_data = JSON.parse(File.read(json_path))

      modified = false
      # Оновлюємо шляхи для кожного матеріалу
      if json_data["materials"]
        json_data["materials"].each do |id, material|
          next unless material["material_type"] == "texture" && material["texture_paths"]

          # Перевіряємо і оновлюємо шляхи до текстур
          ["main", "edge"].each do |texture_type|
            if material["texture_paths"][texture_type]
              old_path = material["texture_paths"][texture_type]
              new_path = File.basename(old_path)
              if old_path != new_path
                material["texture_paths"][texture_type] = new_path
                modified = true
                puts "Оновлено шлях для матеріалу #{id}, текстура #{texture_type}: #{new_path}"
              end
            end
          end
        end
      end

      # Зберігаємо оновлений JSON тільки якщо були зміни
      if modified
        File.write(json_path, JSON.pretty_generate(json_data))
        puts "JSON файл оновлено успішно"
      else
        puts "Оновлення JSON файлу не потрібне"
      end
    rescue StandardError => e
      puts "Помилка при оновленні JSON файлу: #{e.message}"
      puts e.backtrace
    end
  end
  
    # Оновлений метод завантаження файлів
  def self.load_plugin_file(filename)
    rbe_path = File.join(PLUGIN_DIR, "#{filename}.rbe")
    rb_path = File.join(PLUGIN_DIR, "#{filename}.rb")
    
    puts "\nСпроба завантаження модуля #{filename}"
    puts "Перевірка шляху .rbe: #{rbe_path}"
    puts "Перевірка шляху .rb: #{rb_path}"
    
    begin
      if File.exist?(rbe_path)
        puts "Знайдено зашифрований файл (.rbe)"
        begin
          content = File.read(rbe_path)
          puts "Розмір файлу: #{content.size} байт"
          begin
            # Використовуємо повний шлях для завантаження
            Sketchup.load(rbe_path)
            puts "Успішно завантажено #{filename}.rbe"
            return true
          rescue LoadError => e
            puts "LoadError при завантаженні .rbe: #{e.message}"
            if File.exist?(rb_path)
              puts "Спроба завантаження .rb як запасного варіанту"
              load rb_path
              puts "Успішно завантажено #{filename}.rb як запасний варіант"
              return true
            end
          rescue SyntaxError => e
            puts "SyntaxError при завантаженні .rbe: #{e.message}"
            if File.exist?(rb_path)
              puts "Спроба завантаження .rb як запасного варіанту"
              load rb_path
              puts "Успішно завантажено #{filename}.rb як запасний варіант"
              return true
            end
          end
        rescue => e
          puts "Помилка читання файлу #{filename}.rbe:"
          puts "#{e.class}: #{e.message}"
          return false
        end
      elsif File.exist?(rb_path)
        puts "Знайдено незашифрований файл (.rb)"
        begin
          load rb_path
          puts "Успішно завантажено #{filename}.rb"
          return true
        rescue => e
          puts "Помилка при завантаженні #{filename}.rb:"
          puts "#{e.class}: #{e.message}"
          puts e.backtrace.join("\n")
          return false
        end
      else
        puts "ПОМИЛКА: Файл не знайдено: ні #{filename}.rb, ні #{filename}.rbe"
        return false
      end
    rescue => e
      puts "Критична помилка при завантаженні #{filename}:"
      puts "#{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      return false
    end
    false
  end

  def self.install
    begin
      puts "Початок встановлення WWT_CreatePanelsTools..."
      
      # Створюємо необхідні директорії
      [PLUGIN_DIR, ICONS_DIR, TEXTURES_DIR, SETTINGS_DIR].each do |dir|
        unless Dir.exist?(dir)
          puts "Створення директорії: #{dir}"
          FileUtils.mkdir_p(dir)
        end
      end

      # Копіювання текстур і оновлення JSON
      update_json_paths if File.exist?(File.join(SETTINGS_DIR, "panel_defaults.json"))
      
      puts "Встановлення WWT_CreatePanelsTools завершено успішно"
      true
    rescue StandardError => e
      puts "Помилка при встановленні плагіна: #{e.message}"
      puts e.backtrace
      false
    end
  end

  # Метод для отримання стану кнопки
  def self.materials_enabled?
    @materials_button_state
  end
  
  def self.toggle_materials_state
    previous_state = @materials_button_state
    @materials_button_state = !@materials_button_state
    puts "Зміна стану кнопки: #{previous_state} -> #{@materials_button_state}"
    
    if defined?(MaterialAssignerNormalizeScale)
      MaterialAssignerNormalizeScale.functionality_enabled = @materials_button_state
    end
    
    if @cmd_materials_handler
      current_icon = @materials_button_state ? 
        File.join(ICONS_DIR, "MaterialsHandler_on.png") : 
        File.join(ICONS_DIR, "MaterialsHandler_off.png")
        
      @cmd_materials_handler.small_icon = current_icon
      @cmd_materials_handler.large_icon = current_icon
      
      @cmd_materials_handler.tooltip = @materials_button_state ? 
        "Обробка матеріалів увімкнена (натисніть для вимкнення)" : 
        "Обробка матеріалів вимкнена (натисніть для увімкнення)"
      
      puts "Спроба збереження налаштувань..."
      save_settings
      
      puts "Перевірка збережених налаштувань:"
      if File.exist?(SETTINGS_FILE)
        puts File.read(SETTINGS_FILE)
      else
        puts "Файл налаштувань не створено!"
      end
      
      Sketchup.active_model.tools.active_tool_name
      UI.refresh_toolbars
    end
  end
  
  def self.cmd_materials_handler
    @cmd_materials_handler ||= begin
      cmd = UI::Command.new("WWT_Обробка матеріалів") { toggle_materials_state }
      
      cmd.set_validation_proc {
        @materials_button_state ? MF_CHECKED : MF_UNCHECKED
      }
      
      # Виправлена логіка встановлення іконок
      cmd.small_icon = File.join(ICONS_DIR, @materials_button_state ? "MaterialsHandler_on.png" : "MaterialsHandler_off.png")
      cmd.large_icon = File.join(ICONS_DIR, @materials_button_state ? "MaterialsHandler_on.png" : "MaterialsHandler_off.png")
      
      cmd.tooltip = @materials_button_state ? 
        "Обробка матеріалів увімкнена (натисніть для вимкнення)" : 
        "Обробка матеріалів вимкнена (натисніть для увімкнення)"
      cmd.status_bar_text = "Контролює обробку матеріалів"

      cmd
    end
  end

  # Спостерігач для збереження налаштувань при закритті SketchUp
class AppObserverForSettings < Sketchup::AppObserver
    def onQuit
      puts "SketchUp закривається. Зберігаємо налаштування..."
      WWT_CreatePanelsTools.save_settings
    end
  end

  # Клас для перевірки оновлень
  class UpdateChecker
    @update_checked = false

    def self.check_for_updates(show_no_update_message = false)
      return if !show_no_update_message && @update_checked
      @update_checked = true

      begin
        uri = URI("https://raw.githubusercontent.com/WoodWorker1977/WWT_CreatePanelsTools/main/update.json")
        response = Net::HTTP.get(uri)
        data = JSON.parse(response)

        latest_version = data["WWT_CreatePanelsTools"]["version"]
        if newer_version_available?(latest_version)
          show_update_dialog(latest_version, data["WWT_CreatePanelsTools"]["download_url"])
        elsif show_no_update_message
          UI.messagebox("У вас вже встановлена остання версія WWT Create Panels Tools (#{VERSION}).")
        end
      rescue => e
        puts "Помилка перевірки оновлень: #{e.message}"
        if show_no_update_message
          UI.messagebox("Не вдалося перевірити оновлення: #{e.message}")
        end
      end
    end

    private

    def self.newer_version_available?(latest_version)
      Gem::Version.new(latest_version) > Gem::Version.new(VERSION)
    end

    def self.show_update_dialog(new_version, download_url)
      result = UI.messagebox(
        "Доступна нова версія WWT Create Panels Tools (#{new_version})!\n" +
        "Поточна версія: #{VERSION}\n\n" +
        "Бажаєте завантажити оновлення?",
        MB_YESNO
      )

      if result == IDYES
        UI.openURL(download_url)
        UI.messagebox(
          "Після завантаження:\n" +
          "1. Видаліть поточну версію плагіна WWT_CreatePanelsTools v#{VERSION}\n" +
          "2. Перезапустіть SketchUp\n" +
          "3. Встановіть нову версію WWT_CreatePanelsTools v#{new_version}\n"
        )
      end
    end
  end

  # Метод для повного перезавантаження плагіну
  def self.reload
    puts "Починається перезавантаження плагіну WWT_CreatePanelsTools..."
    
    # Зупиняємо активний інструмент
    Sketchup.active_model.select_tool(nil) if Sketchup.active_model.tools.active_tool_id > 0
    
    # Очищаємо тулбар
    if UI::Toolbar.all.include?("WWT_CreatePanelsTools")
      toolbar = UI::Toolbar.new("WWT_CreatePanelsTools")
      toolbar.hide
      toolbar = nil
    end
    
    # Видаляємо константи модулів
    constants_to_remove = self.constants.select do |const|
      const_name = const.to_s
      # Не видаляємо версію та важливі константи
      !['VERSION', 'PLUGIN_ROOT', 'PLUGIN_DIR', 'ICONS_DIR', 'TEXTURES_DIR', 'SETTINGS_DIR', 'SETTINGS_FILE'].include?(const_name)
    end
    
    constants_to_remove.each do |const|
      remove_const(const) rescue nil
    end
    
    # Позначаємо файли як незавантажені
    files_pattern = File.join(PLUGIN_DIR, "*.{rb,rbe}")
    Dir.glob(files_pattern).each do |file|
      $LOADED_FEATURES.reject! { |path| path == file }
    end
    
    # Зберігаємо налаштування
    save_settings
    
    # Перезавантажуємо основний файл
    load __FILE__
    
    puts "Плагін WWT_CreatePanelsTools успішно перезавантажено!"
  end
  
  # Команда для перезавантаження плагіну
  def self.cmd_reload
    cmd = UI::Command.new("Перезавантажити WWT_CreatePanelsTools") { reload }
    cmd.small_icon = File.join(ICONS_DIR, "reload.png") # Якщо є така іконка
    cmd.large_icon = File.join(ICONS_DIR, "reload.png") # Якщо є така іконка
    cmd.tooltip = "Перезавантажити плагін WWT_CreatePanelsTools"
    cmd.status_bar_text = "Повністю перезавантажує плагін WWT_CreatePanelsTools"
    cmd
  end

  # Головний блок ініціалізації
  unless file_loaded?(__FILE__)
    begin
      # Виконуємо інсталяцію при першому завантаженні
      install

      # Завантажуємо збережені налаштування
      load_settings

      # Додаємо спостерігач за закриттям програми
      Sketchup.add_observer(AppObserverForSettings.new)

      # Реєстрація розширення
      ext = SketchupExtension.new(
        "WWT_CreatePanelsTools",
        if File.exist?(File.join(PLUGIN_DIR, "WWT_CreatePanelArray.rbe"))
          File.join(PLUGIN_DIR, "WWT_CreatePanelArray.rbe")
        else
          File.join(PLUGIN_DIR, "WWT_CreatePanelArray.rb")
        end
      )

      ext.description = 'Підбірка плагінів мебляра від SketchUp Ukraine'
      ext.version     = "#{VERSION} (11.07.2024)"  # Оновлено дату
      ext.creator     = "Ruslan https://t.me/SketchUp_Ukraine"
      ext.copyright   = 'SketchUp Ukraine 2024 (https://t.me/SketchUp_Ukraine)'

      Sketchup.register_extension(ext, true)

      # Завантаження всіх модулів
      files = [
        'WWT_Adaptations_to_axes_XYZ',
        'WWT_CreateSinglePanel',
        'WWT_CreatePanelArray',
        'WWT_ExtrudeFaceTool',  # Додано новий файл до списку завантаження
        'WWT_CustomScaleToolNumber',
        'WWT_Dividers',
        'WWT_MaterialAssignerNormalizeScale',
        'WWT_Positioning'
      ]

      # Завантажуємо кожен файл
      load_errors = []
      files.each do |file|
        unless load_plugin_file(file)
          load_errors << file
        end
      end

      # Створення тулбару
      toolbar = UI::Toolbar.new "WWT_CreatePanelsTools"

      # Кнопка для створення одиничної панелі
      cmd_single_panel = UI::Command.new("WWT_Створити панель >>>") {
        if defined?(WWT_CreatePanelsTools::WWT_CreateSinglePanel::CreateSinglePanel)
          Sketchup.active_model.select_tool(WWT_CreatePanelsTools::WWT_CreateSinglePanel::CreateSinglePanel.new)
        else
          UI.messagebox("Модуль WWT_CreatePanelsTools::WWT_CreateSinglePanel не знайдено")
        end
      }
      cmd_single_panel.small_icon = File.join(ICONS_DIR, "CreatePanel.png")
      cmd_single_panel.large_icon = File.join(ICONS_DIR, "CreatePanel.png")
      cmd_single_panel.tooltip = "Створення меблевої панелі"
      cmd_single_panel.status_bar_text = "Створює меблеві панелі"
      toolbar.add_item(cmd_single_panel)

      # Кнопка для створення масиву панелей
      cmd_panel_array = UI::Command.new("WWT_Створити масив панелей >>>") {
        if defined?(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool)
          Sketchup.active_model.select_tool(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool.new)
        else
          UI.messagebox("Модуль WWT_CreatePanelsTools::WWT_CreatePanelArray не знайдено")
        end
      }
      cmd_panel_array.small_icon = File.join(ICONS_DIR, "CreatePanelArray.png")
      cmd_panel_array.large_icon = File.join(ICONS_DIR, "CreatePanelArray.png")
      cmd_panel_array.tooltip = "Створити масив панелей"
      cmd_panel_array.status_bar_text = "Створює масив панелей"
      toolbar.add_item(cmd_panel_array)

      # Нова кнопка для інструменту екструзії граней
      cmd_extrude_face = UI::Command.new("WWT_Екструзія грані >>>") {
        if defined?(WWT_CreatePanelsTools::WWT_ExtrudeFaceTool)
          WWT_CreatePanelsTools::WWT_ExtrudeFaceTool.run_tool
        else
          UI.messagebox("Модуль WWT_CreatePanelsTools::WWT_ExtrudeFaceTool не знайдено")
        end
      }
      cmd_extrude_face.small_icon = File.join(ICONS_DIR, "extrude_face_small.png")
      cmd_extrude_face.large_icon = File.join(ICONS_DIR, "extrude_face_large.png")
      cmd_extrude_face.tooltip = "Екструзія грані з налаштуваннями"
      cmd_extrude_face.status_bar_text = "Створює об'єкт шляхом екструзії грані з можливістю налаштування відступів"
      toolbar.add_item(cmd_extrude_face)

      # Додавання кнопки обробки матеріалів
      toolbar.add_item(cmd_materials_handler)

      # Показуємо тулбар
      toolbar.restore
      toolbar.show

      # Додаємо меню для перевірки оновлень і перезавантаження
      if !@update_menu_added
        menu = UI.menu("Plugins")
        menu.add_item("Перевірити оновлення WWT_CreatePanelsTools") {
          UpdateChecker.check_for_updates(true)
        }
        menu.add_item("Перезавантажити WWT_CreatePanelsTools") { 
          reload 
        }
        @update_menu_added = true
      end

      # Автоматична перевірка оновлень при завантаженні
      UI.start_timer(15.0, false) { UpdateChecker.check_for_updates }

      if load_errors.any?
        UI.messagebox("Помилка завантаження наступних модулів:\n#{load_errors.join("\n")}\nПеревірте журнал Ruby Console для деталей.")
      end

    rescue => e
      puts "Критична помилка при ініціалізації плагіна:"
      puts "#{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
      UI.messagebox("Виникла помилка при ініціалізації плагіна. Перевірте журнал Ruby Console для деталей.")
    end

    file_loaded(__FILE__)
  end
end
