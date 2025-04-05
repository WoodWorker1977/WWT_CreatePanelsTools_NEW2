# Утиліта для перевірки та виправлення контекстного меню

module WWT_CreatePanelsTools
  module MenuValidator
    def self.verify_context_menu
      tool = Sketchup.active_model.tools.active_tool
      
      puts "=== Перевірка налаштувань контекстного меню ==="
      
      if tool.nil?
        puts "Помилка: нема активного інструмента!"
        return false
      end
      
      puts "Активний інструмент: #{tool.class}"
      
      if tool.is_a?(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool)
        puts "Виявлено інструмент WWT_CreatePanelArray::CubTool"
        
        # Перевіряємо доступність методів
        has_rbdown = tool.public_methods.include?(:onRButtonDown)
        has_getmenu = tool.public_methods.include?(:getMenu)
        
        puts "onRButtonDown публічний?: #{has_rbdown}"
        puts "getMenu публічний?: #{has_getmenu}"
        
        # Тестуємо створення меню
        if has_getmenu
          begin
            menu = UI::Menu.new
            tool.getMenu(menu)
            
            if menu.instance_variable_get(:@items) && !menu.instance_variable_get(:@items).empty?
              puts "Успіх: Меню містить #{menu.instance_variable_get(:@items).size} пунктів"
            else
              puts "Увага: Меню порожнє! Це може спричинити проблеми."
            end
          rescue => e
            puts "Помилка при тестуванні getMenu: #{e.message}"
          end
        end
        
        return has_rbdown && has_getmenu
      else
        puts "Увага: Активний інструмент не є WWT_CreatePanelArray::CubTool"
        puts "Активуйте правильний інструмент перед перевіркою."
        return false
      end
    end
    
    def self.quick_test
      if verify_context_menu
        UI.messagebox("Тест пройдено успішно! Контекстне меню має бути доступне.")
      else
        result = UI.messagebox("Виявлено проблеми з контекстним меню. Спробувати виправити?", MB_YESNO)
        fix_context_menu if result == IDYES
      end
    end
    
    def self.fix_context_menu
      tool = Sketchup.active_model.tools.active_tool
      
      unless tool.is_a?(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool)
        UI.messagebox("Активуйте інструмент WWT_Створити масив панелей перед виправленням.")
        return false
      end
      
      # Зупиняємо і перезапускаємо інструмент
      Sketchup.active_model.select_tool(nil)
      
      # Перезавантажуємо плагін
      if WWT_CreatePanelsTools.respond_to?(:reload)
        WWT_CreatePanelsTools.reload
        UI.messagebox("Плагін перезавантажено. Спробуйте активувати інструмент знову.")
      else
        # Запускаємо новий екземпляр інструменту
        Sketchup.active_model.select_tool(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool.new)
        UI.messagebox("Інструмент перезапущено. Спробуйте використовувати праву кнопку миші.")
      end
      
      true
    end
  end
end

# Додаємо команди до меню
unless file_loaded?(__FILE__)
  menu = UI.menu("Plugins").add_submenu("WWT Діагностика")
  
  menu.add_item("Перевірити контекстне меню") {
    WWT_CreatePanelsTools::MenuValidator.quick_test
  }
  
  menu.add_item("Виправити контекстне меню") {
    WWT_CreatePanelsTools::MenuValidator.fix_context_menu
  }
  
  file_loaded(__FILE__)
end

puts "Утиліта перевірки контекстного меню завантажена."
puts "Виберіть 'Plugins > WWT Діагностика > Перевірити контекстне меню' для тестування."
