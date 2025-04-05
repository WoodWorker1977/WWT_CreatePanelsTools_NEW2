# Утиліта для швидкого тестування контекстного меню

module WWT_CreatePanelsTools
  module ContextMenuTest
    def self.test_context_menu
      # Отримуємо активний інструмент
      tool = Sketchup.active_model.tools.active_tool
      
      puts "=== Тестування контекстного меню ==="
      puts "Активний інструмент: #{tool.class}"
      
      if tool.nil?
        puts "ПОМИЛКА: Немає активного інструменту!"
        return false
      end
      
      # Перевіряємо чи це наш інструмент
      if tool.is_a?(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool)
        puts "Це інструмент WWT_CreatePanelArray::CubTool - добре!"
        
        # Перевіряємо доступність методів
        methods = tool.methods
        public_methods = tool.public_methods
        
        puts "Метод onRButtonDown публічний? #{public_methods.include?(:onRButtonDown)}"
        puts "Метод getMenu публічний? #{public_methods.include?(:getMenu)}"
        
        # Тестуємо виклик getMenu напряму
        begin
          menu = UI::Menu.new
          tool.getMenu(menu)
          item_count = menu.instance_variable_get(:@items)&.size || 0
          puts "getMenu успішно створив меню з #{item_count} елементами"
        rescue => e
          puts "ПОМИЛКА при виклику getMenu: #{e.message}"
          puts e.backtrace.join("\n")
        end
        
        # Порада щодо вирішення проблеми
        puts "\nЯкщо контекстне меню не з'являється:"
        puts "1. Переконайтеся, що методи onRButtonDown і getMenu знаходяться ПЕРЕД блоком 'private'"
        puts "2. Перезавантажте плагін: Plugins > Перезавантажити WWT_CreatePanelsTools"
        puts "3. Запустіть інструмент масиву панелей знову"
        
        return true
      else
        puts "ПОМИЛКА: Активний інструмент не є WWT_CreatePanelArray::CubTool"
        puts "Будь ласка, активуйте інструмент WWT_Створити масив панелей"
        return false
      end
    end
    
    # Зручний скрипт для запуску через Ruby Console
    def self.quick_fix
      # Відключаємо поточний інструмент
      Sketchup.active_model.select_tool(nil)
      
      # Перезавантажуємо файл
      file_path = File.join(WWT_CreatePanelsTools::PLUGIN_ROOT, 'WWT_CreatePanelsTools', 'WWT_CreatePanelArray.rb')
      if File.exist?(file_path)
        puts "Перезавантаження файлу: #{file_path}"
        load file_path
        puts "Файл перезавантажено"
      else
        puts "Файл не знайдено: #{file_path}"
      end
      
      # Запускаємо інструмент заново
      Sketchup.active_model.select_tool(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool.new)
      puts "Інструмент перезапущено"
    end
  end
end

# Додаємо команди до меню
if !$context_menu_test_loaded
  menu = UI.menu("Plugins").add_submenu("WWT Тестування")
  
  cmd_test = UI::Command.new("Перевірити контекстне меню") {
    WWT_CreatePanelsTools::ContextMenuTest.test_context_menu
  }
  
  cmd_fix = UI::Command.new("Швидке виправлення меню") {
    WWT_CreatePanelsTools::ContextMenuTest.quick_fix
  }
  
  menu.add_item(cmd_test)
  menu.add_item(cmd_fix)
  
  $context_menu_test_loaded = true
end

puts "=== Утиліта тестування контекстного меню завантажена ==="
puts "Виконайте в Ruby Console:"
puts "WWT_CreatePanelsTools::ContextMenuTest.test_context_menu  # Для перевірки"
puts "WWT_CreatePanelsTools::ContextMenuTest.quick_fix          # Для швидкого виправлення"
