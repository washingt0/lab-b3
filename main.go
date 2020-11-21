package main

import (
	"encoding/csv"
	"errors"
	"log"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"

	"go.uber.org/zap"
)

type ANA struct {
	PeriodStart time.Time
	PeriodEnd   time.Time
	Account     *int64
	BankCode    *int64
	BankName    *string
	Trading     []Trade
}

type Trade struct {
	Date             time.Time
	Operation        *string
	Market           *string
	DueDate          *string
	StockCode        *string
	StockDescription *string
	Amount           *int64
	Value            *int64
	Total            *int64
}

type parseFunc func(x, y int, data *[][]string, ana *ANA) (err error)

func main() {
	var (
		f               *os.File
		err             error
		records         [][]string
		interestHeaders = map[string]parseFunc{
			"Período de":                 parsePeriod,
			"Participante de Negociação": parseAccount,
			"Código / Nome":              parseBank,
			"Data Negócio":               parseTrading,
		}
		ana *ANA = new(ANA)
	)
	file := "InfoCEI.csv"

	logger, _ := zap.NewDevelopment()
	defer logger.Sync() // flushes buffer, if any

	if f, err = os.Open(file); err != nil {
		log.Fatal(err)
	}

	if records, err = csv.NewReader(f).ReadAll(); err != nil {
		log.Fatal(err)
	}

	for i := range records {

		if ana.Trading != nil {
			break
		}

		for j := range records[i] {
			for k := range interestHeaders {
				if strings.Contains(records[i][j], k) {
					if err = interestHeaders[k](i, j, &records, ana); err != nil {
						log.Fatal(err)
					}
				}
			}
		}
	}

	logger.Debug("ana", zap.Any("ANA", ana))
}

func parsePeriod(x, y int, data *[][]string, ana *ANA) (err error) {
	splt := strings.Split((*data)[x+1][y], " a ")

	if len(splt) != 2 {
		return errors.New("Periodo do arquivo invalido")
	}

	if ana.PeriodStart, err = time.Parse("02/01/2006", splt[0]); err != nil {
		return errors.New("Data inicial invalida")
	}

	if ana.PeriodEnd, err = time.Parse("02/01/2006", splt[1]); err != nil {
		return errors.New("Data final invalida")
	}

	return
}

func parseAccount(x, y int, data *[][]string, ana *ANA) (err error) {
	var (
		accNum int64
	)

	if accNum, err = strconv.ParseInt(strings.Split((*data)[x+1][y], " - ")[1], 10, 64); err != nil {
		return errors.New("Participante invalido")
	}

	ana.Account = &accNum

	return
}

func parseBank(x, y int, data *[][]string, ana *ANA) (err error) {
	var (
		splt     []string = strings.Split((*data)[x+1][y], " - ")
		bankCode int64
	)

	if len(splt) < 2 {
		return errors.New("instituição financeira invalida")
	}

	if bankCode, err = strconv.ParseInt(splt[0], 10, 64); err != nil {
		return errors.New("Código de instituição invalido")
	}

	ana.BankCode = &bankCode
	ana.BankName = getStringPointer(strings.Join(splt[1:], " - "))

	return
}

func getStringPointer(s string) *string {
	return &s
}

func getInt64Pointer(i int64) *int64 {
	return &i
}

func parseTrading(x, y int, data *[][]string, ana *ANA) (err error) {
	if (*data)[x+1][y] == "" || !strings.Contains((*data)[x][y+2], "C/V") {
		return errors.New("Arquivo sem movimentação ou invalido")
	}

	if ana.Trading != nil {
		return
	}

	ana.Trading = make([]Trade, 0, len((*data)[x+1:]))

	for i := range (*data)[x+1:] {
		var t Trade

		if _, err = time.Parse("02/01/06", strings.TrimSpace((*data)[x+1+i][1])); err != nil {
			err = nil
			break
		}

		if t, err = parseTrade(&(*data)[x+1+i]); err != nil {
			return
		}

		ana.Trading = append(ana.Trading, t)
	}

	return
}

func parseTrade(row *[]string) (out Trade, err error) {
	const (
		_dateIndex             = 1
		_operationIndex        = 3
		_marketIndex           = 4
		_dueDateIndex          = 5
		_stockCodeIndex        = 6
		_stockDescriptionIndex = 7
		_amountIndex           = 8
		_valueIndex            = 9
		_totalIndex            = 10
	)

	for i := range *row {
		(*row)[i] = strings.TrimSpace((*row)[i])
	}

	if out.Date, err = time.Parse("02/01/06", (*row)[_dateIndex]); err != nil {
		return out, errors.New("data de negócio invalida")
	}

	if out.Operation = getStringPointer((*row)[_operationIndex]); *out.Operation != "C" && *out.Operation != "V" {
		return out, errors.New("tipo de operacao invalida")
	}

	if out.Market = getStringPointer((*row)[_marketIndex]); *out.Market == "" {
		return out, errors.New("mercado invalido")
	}

	re := regexp.MustCompile(`\s+`)

	out.DueDate = getStringPointer((*row)[_dueDateIndex])

	out.StockCode = getStringPointer((*row)[_stockCodeIndex])

	out.StockDescription = getStringPointer(re.ReplaceAllString((*row)[_stockDescriptionIndex], " "))

	var tmp int64

	if tmp, err = strconv.ParseInt((*row)[_amountIndex], 10, 64); err != nil {
		return out, errors.New("Quantidade invalida")
	}

	out.Amount = getInt64Pointer(tmp)

	re = regexp.MustCompile(`[^\d]`)

	if tmp, err = strconv.ParseInt(re.ReplaceAllString((*row)[_valueIndex], ""), 10, 64); err != nil {
		return out, err
	}

	out.Value = getInt64Pointer(tmp)

	if tmp, err = strconv.ParseInt(re.ReplaceAllString((*row)[_totalIndex], ""), 10, 64); err != nil {
		return out, errors.New("Valor total invalido")
	}

	out.Total = getInt64Pointer(tmp)

	return
}
