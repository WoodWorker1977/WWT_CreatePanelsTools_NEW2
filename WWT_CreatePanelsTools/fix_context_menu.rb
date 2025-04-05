# Скрипт для швидкого виправлення проблеми з контекстним меню

module WWT_CreatePanelsTools
  module ContextMenuFixer
    def self.fix_context_menu_issue
      puts "Виконується налагодження контекстного меню..."
      tool = Sketchup.active_model.tools.active_tool
      
      # Перевіряємо наявність інструмента
      if tool.nil?
        puts "Помилка: немає активного інструмента!"
        UI.messagebox("Активуйте інструмент WWT_CreatePanelArray перед запуском виправлення.")
        return false
      end
      
      # Перевіряємо тип інструмента
      unless tool.is_a?(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool)
        puts "Помилка: активний інструмент не є WWT_CreatePanelArray!"
        UI.messagebox("Активуйте інструмент WWT_CreatePanelArray перед запуском виправлення.")
        return false
      end
      
      # Додаємо методи меню як публічні напряму у живий екземпляр інструмента
      tool.instance_eval do
        def onRButtonDown(flags, x, y, view)
          puts "Викликається перевизначений onRButtonDown"
          begin
            @view = view
            menu = UI::Menu.new
            begin
              # Спробуємо додати пункти напряму, якщо getMenu не працює
              menu.add_item("Налаштування масиву панелей") do
                if respond_to?(:valid_preview_state?) && valid_preview_state?
                  if @ctrl_pressed
                    respond_to?(:show_custom_dialog_array) ? show_custom_dialog_array : UI.messagebox("Метод show_custom_dialog_array недоступний")
                  else
                    respond_to?(:show_custom_dialog_basic) ? show_custom_dialog_basic : UI.messagebox("Метод show_custom_dialog_basic недоступний")
                  end
                else
                  UI.messagebox("Для налаштувань, наведіть курсор на обличку деталі")
                end
              end
              
              menu.add_separator
              
              menu.add_item("Тестове повідомлення") do
                UI.messagebox("Контекстне меню працює!")
              end
              
            rescue => e
              puts "Помилка при створенні пунктів меню: #{e}"
            end
            
            puts "Показуємо контекстне меню на #{x},#{y}"
            menu.popup(x, y)
            true
          rescue => e
            puts "Критична помилка в onRButtonDown: #{e}"
            false
          end
        end
      end
      
      puts "Методи меню додані до активного інструмента!"
      UI.messagebox("Фіксація завершена! Спробуйте натиснути ПКМ на панелі.")
      true
    end
    
    def self.restart_tool
      puts "Перезапуск інструмента..."
      Sketchup.active_model.select_tool(nil)
      Sketchup.active_model.select_tool(WWT_CreatePanelsTools::WWT_CreatePanelArray::CubTool.new)
      puts "Інструмент перезапущено!"
      UI.messagebox("Інструмент перезапущено. Спробуйте використовувати ПКМ.")
    end
  end
end

# Додаємо пункти меню для виклику наших методів
unless file_loaded?(__FILE__)
  menu = UI.menu("Plugins").add_submenu("WWT Фіксація")
  
  menu.add_item("Виправити контекстне меню") {
    WWT_CreatePanelsTools::ContextMenuFixer.fix_context_menu_issue
  }
  
  menu.add_item("Перезапустити інструмент") {
    WWT_CreatePanelsTools::ContextMenuFixer.restart_tool
  }
  
  file_loaded(__FILE__)
end

puts "Скрипт виправлення контекстного меню завантажено!"
puts "Виберіть 'Plugins > WWT Фіксація > Виправити контекстне меню' під час використання інструменту"
