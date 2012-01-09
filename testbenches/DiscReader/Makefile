TARGET	:= tb_DiscReader
VLOGFILES	:= main.v

.PHONY:	test clean

test:	$(TARGET)
	vvp $(TARGET)

clean:
	rm -f $(TARGET) *~

$(TARGET): $(VLOGFILES)
	iverilog -o $@ $^
