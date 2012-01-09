TARGET	:= tb_DiscReader
VLOGFILES	:= \
	../../Flag_Delay1tcy_OneCycle.v \
	../../DiscReader.v \
	main.v

.PHONY:	test clean

test:	$(TARGET)
	vvp $(TARGET)

clean:
	rm -f $(TARGET) *~

$(TARGET): $(VLOGFILES)
	iverilog -o $@ $^
