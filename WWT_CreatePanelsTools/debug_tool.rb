# Утиліта для діагностики проблем з інструментами

module WWT_CreatePanelsTools
  module DebugTool
    def self.check_tool_context_menu
      # Перевіряємо активний інструмент
      tool = Sketchup.active_model.tools.active_tool
      puts "=== Діагностика контекстного меню ==="
      
      if tool.nil?
        puts "Помилка: Немає активного інструменту!"
        return false
      end
      
      puts "Активний інструмент: #{tool.class}"
      
      # Перевіряємо, чи має інструмент необхідні методи
      has_rbdown = tool.respond_to?(:onRButtonDown)
      has_getmenu = tool.respond_to?(:getMenu)
      
      puts "onRButtonDown: #{has_rbdown ? 'Є' : 'Відсутній'}"
      puts "getMenu: #{has_getmenu ? 'Є' : 'Відсутній'}"
      
      if !has_rbdown
        puts "ПРОБЛЕМА: Відсутній метод onRButtonDown - меню ПКМ не буде працювати."
        return false
      end
      
      if !has_getmenu
        puts "ПРОБЛЕМА: Відсутній метод getMenu - onRButtonDown не зможе наповнити меню."
        return false
      end
      
      # Тестуємо створення меню
      begin
        menu = UI::Menu.new
        tool.send(:getMenu, menu) if has_getmenu
        
        if menu.instance_variable_get(:@items) && !menu.instance_variable_get(:@items).empty?
          puts "Успіх: меню містить #{menu.instance_variable_get(:@items).size} пунктів"
        else
          puts "ПРОБЛЕМА: меню порожнє!"
          return false
        end
      rescue => e
        puts "ПОМИЛКА при тестуванні меню: #{e.message}"
        puts e.backtrace.join("\n")
        return false
      end
      
      puts "Всі базові перевірки пройдені успішно!"
      puts "Якщо меню все одно не з'являється, проблема може бути в:"
      puts "1. Конфліктах з іншими інструментами"
      puts "2. Неправильних координатах меню"
      puts "3. Затриманні події правого кліку іншими обробниками"
      
      true
    end
    
    def self.fix_context_menu
      puts "Перезавантаження інструментів..."
      
      # Деактивуємо всі інструменти
      Sketchup.active_model.select_tool(nil)
      
      if defined?(WWT_CreatePanelsTools::WWT_CreatePanelArray)
        puts "Перезавантаження WWT_CreatePanelArray..."
        WWT_CreatePanelsTools::WWT_CreatePanelArray.reload_tool if WWT_CreatePanelsTools::WWT_CreatePanelArray.respond_to?(:reload_tool)
      end
      
      puts "Фіксація завершена. Спробуйте тепер використовувати ПКМ."
    end
  end
end

# Виведення інструкцій для використання
puts "=== Інструмент діагностики завантажено ==="
puts "Для діагностики виконайте: WWT_CreatePanelsTools::DebugTool.check_tool_context_menu"
puts "Для спроби виправлення проблем виконайте: WWT_CreatePanelsTools::DebugTool.fix_context_menu"
